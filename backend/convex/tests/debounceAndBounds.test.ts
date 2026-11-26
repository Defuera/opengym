import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../functions/_generated/api";
import { REBUILD_DEBOUNCE_MS } from "../functions/lib/constants";
import { boundedPlanSessions, buildReviewInput, DASHBOARD_RECENT, PLAN_RECENT_ANY, PLAN_RECENT_OF_TYPE, REVIEW_RECENT_OF_TYPE } from "../functions/model/ai/jobs/inputs";
import type { Session } from "../functions/model/schema";
import { TOKEN, pushSession, setup, settle, stubOpenAi, type T } from "./helpers";

let t: T;
const save = (s: ReturnType<typeof pushSession>) => t.mutation(api.commands.sessions.save, { token: TOKEN, session: s });
const state = () => t.run((c) => c.db.query("rebuilds").first());

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(Date.UTC(2026, 0, 15, 12));
  t = setup();
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

describe("debounce", () => {
  it("10 session saves lead to one rebuild run, not ten", async () => {
    const calls = stubOpenAi(() => "{}"); // every answer is invalid -> fallback; we only count the calls
    for (let i = 0; i < 10; i++) await save(pushSession(`s${i}`, 1_000_000 * (i + 1)));
    await settle(t);
    expect((await state())!.runs).toBe(1);
    const n = (job: string) => calls.filter((c) => c.job === job && c.input !== undefined).length;
    // Fallback happens after one retry, so each job calls the provider twice.
    expect(n("plan_session") / 2).toBe(1); // only the focus in the log (Gym Push), once
    expect(n("predict_activity")).toBe(0); // the AI predict job is no longer scheduled
    expect(n("build_dashboard") / 2).toBe(2); // 7 and 30 days
    expect(n("review_session") / 2).toBe(10); // one review per saved session
    expect(await t.run((c) => c.db.query("plans").collect())).toHaveLength(1);
  });

  it("writes during the quiet window push the runner back; a later burst runs again", async () => {
    await save(pushSession("a", 1_000_000));
    await vi.advanceTimersByTimeAsync(REBUILD_DEBOUNCE_MS - 1_000);
    await save(pushSession("b", 2_000_000)); // still inside the window: the runner re-checks and waits again
    await vi.advanceTimersByTimeAsync(2_000);
    await t.finishInProgressScheduledFunctions();
    expect((await state())!.runs).toBe(0);
    await settle(t);
    expect((await state())!.runs).toBe(1);
    await save(pushSession("c", 3_000_000));
    await settle(t);
    expect((await state())!.runs).toBe(2);
  });

  it("a resend of an unchanged session does not ask for a rebuild", async () => {
    await save(pushSession("a", 1_000_000));
    await settle(t);
    await save(pushSession("a", 1_000_000));
    expect((await state())!.runnerScheduled).toBe(false);
    await settle(t);
    expect((await state())!.runs).toBe(1);
  });

  it("a rebuild result older than the stored one is dropped", async () => {
    await t.run(async (c) => {
      await c.db.insert("plans", { activity: "Gym", activityKey: "gym", focusKey: "push", focus: "Push", version: 200, createdAt: 1, source: "ai", rationale: "newer", exercises: [] });
    });
    await t.mutation(internal.jobs.plans.save, { userId: "owner", activity: "Gym", focus: "Push", version: 100, source: "rules", draft: { rationale: "older", exercises: [] } });
    expect(await t.run((c) => c.db.query("plans").collect())).toMatchObject([{ rationale: "newer", version: 200 }]);
  });
});

/** 40 sessions, oldest first. Session 0 holds the heaviest bench ever (100 kg). */
const forty = (): Session[] =>
  Array.from({ length: 40 }, (_, i) => {
    const p = pushSession(`s${i}`, 1_000_000 * (i + 1), i === 0 ? 100 : 40, i % 4 === 3 ? "Pull" : "Push");
    const { sessionId, ...rest } = p;
    return { id: sessionId, ...rest };
  });

describe("bounded model input (pure)", () => {
  it("plan: last 6 gym sessions of the focus plus last 6 of any kind, deduplicated, oldest first", () => {
    const all = forty();
    const got = boundedPlanSessions(all, "Gym", "Pull");
    const expected = new Set([...all.filter((s) => s.kind === "gym" && s.focus === "Pull").slice(-PLAN_RECENT_OF_TYPE), ...all.slice(-PLAN_RECENT_ANY)].map((s) => s.id));
    expect(got.map((s) => s.id)).toEqual(all.filter((s) => expected.has(s.id)).map((s) => s.id));
    expect(got.length).toBeLessThanOrEqual(PLAN_RECENT_OF_TYPE + PLAN_RECENT_ANY);
    expect(got.length).toBe(new Set(got.map((s) => s.id)).size);
  });

  it("review: the session plus the last 6 of the same activity and focus before it", () => {
    const all = forty();
    const s = all[37]!; // a Pull
    const input = buildReviewInput(all, s);
    expect(input.sessions).toHaveLength(REVIEW_RECENT_OF_TYPE + 1);
    expect(input.sessions.every((x) => x.type === s.type && x.focus === s.focus)).toBe(true);
    expect(input.sessions[input.sessions.length - 1]).toBe(s);
    expect(input.sessions.every((x) => x.endedAt <= s.endedAt)).toBe(true);
  });
});

describe("bounded model input (in the database)", () => {
  it("40 sessions in the db: the plan job input is bounded, the limits step still sees all", async () => {
    for (const s of forty()) await save(pushSession(s.id, s.endedAt, s.id === "s0" ? 100 : 40, s.focus));
    await settle(t);

    const input = await t.query(internal.jobs.plans.input, { userId: "owner", activity: "Gym", focus: "Push" });
    expect(input.sessions.length).toBeLessThanOrEqual(PLAN_RECENT_OF_TYPE + PLAN_RECENT_ANY);
    expect(input.sessions.some((s) => s.id === "s0")).toBe(false); // the 100 kg session is outside the model input
    expect(input.rules.exercises.length).toBeGreaterThan(0);

    // The model asks for 500 kg bench. The cap comes from the heaviest ever (100 kg in s0 -> 125), not from the model input (40 kg -> 50).
    await t.mutation(internal.jobs.plans.save, { userId: "owner", 
      activity: "Gym",
      focus: "Push",
      version: Date.now(),
      source: "ai",
      draft: { rationale: "r", exercises: [{ name: "Bench press", sets: [{ reps: 5, kg: 500, max: false }] }] },
    });
    const { plan } = await t.query(api.queries.plans.next, { token: TOKEN, focus: "Push" });
    expect(plan.exercises[0]!.sets[0]!.kg).toBe(125);

    const dash = await t.query(internal.jobs.dashboards.input, { userId: "owner", days: 7 });
    expect(dash.sessions).toHaveLength(DASHBOARD_RECENT);
    const rev = await t.query(internal.jobs.reviews.input, { userId: "owner", sessionId: "s37" });
    expect(rev!.sessions).toHaveLength(REVIEW_RECENT_OF_TYPE + 1);
  });

  it("the prompt the model gets holds only the bounded history", async () => {
    const calls = stubOpenAi(() => "{}");
    for (const s of forty()) await t.run(async (c) => void (await c.db.insert("sessions", { sessionId: s.id, kind: s.kind, type: s.type, focus: s.focus, startedAt: s.startedAt, endedAt: s.endedAt, exercises: s.exercises, source: "app" })));
    await save(pushSession("s40", 41_000_000, 40, "Push"));
    await settle(t);
    const plan = calls.find((c) => c.job === "plan_session" && c.input.focus === "Push")!;
    expect(plan.input.recentLog.length).toBeLessThanOrEqual(PLAN_RECENT_OF_TYPE + PLAN_RECENT_ANY);
  });
});
