import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "../functions/_generated/api";
import { TOKEN, pushSession, setup, settle, stubOpenAi, type T } from "./helpers";

let t: T;
const save = (s: ReturnType<typeof pushSession>) => t.mutation(api.commands.sessions.save, { token: TOKEN, session: s });
const next = (focus = "Push") => t.query(api.queries.plans.next, { token: TOKEN, focus });
const names = (p: { exercises: { name: string }[] }) => p.exercises.map((e) => e.name);

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

describe("rules answers (AI off, nothing stored)", () => {
  it("with no history the plan is empty: no starter template, no invented exercises", async () => {
    const { plan, stored } = await next();
    expect(stored).toBe(false);
    expect(plan.source).toBe("rules");
    expect(plan.exercises).toEqual([]);
    expect(plan.rationale).toContain("Start empty");
    expect((await next("Pull")).plan.exercises).toEqual([]);
  });

  it("after logging a Push session the plan repeats it", async () => {
    const s = pushSession("p1", 5_000_000, 70);
    await save(s);
    const { plan } = await next();
    expect(names(plan)).toEqual(["Bench press", "Dips"]);
    expect(plan.exercises[0]!.sets).toEqual(s.exercises[0]!.sets);
  });

  it("dashboard numbers are computed by code from facts", async () => {
    await save(pushSession("p1", Date.now() - 3_600_000, 60));
    await t.mutation(api.commands.goals.create, { token: TOKEN, goalId: "g1", title: "Bench 80", kind: "strength", exercise: "Bench press", targetKg: 80 });
    const { dashboard, stored } = await t.query(api.queries.dashboard.get, { token: TOKEN, days: 7 });
    expect(stored).toBe(false);
    expect(dashboard).toMatchObject({ days: 7, source: "rules" });
    expect(dashboard.modules.map((m) => m.type)).toEqual(["stat", "stat", "stat", "goal_progress", "recent_sessions"]);
    expect(dashboard.modules[0]).toMatchObject({ value: "1", highlighted: true });
    expect(dashboard.modules[2]).toMatchObject({ value: "60 kg" });
    expect(dashboard.modules[3]).toMatchObject({ current: "60 kg", target: "80 kg", fraction: 0.75 });
    await expect(t.query(api.queries.dashboard.get, { token: TOKEN, days: 9 as never })).rejects.toThrow();
  });

  it("review is the rules review until the job has stored one; unknown session gives null", async () => {
    await save(pushSession("p1", 5_000_000, 60));
    await save(pushSession("p2", 6_000_000, 70));
    const r = await t.query(api.queries.reviews.get, { token: TOKEN, sessionId: "p2" });
    expect(r.stored).toBe(false);
    expect(r.review).toMatchObject({ source: "rules" });
    expect(r.review!.changes.join(" ")).toContain("Bench press: top set 70 kg (was 60 kg)");
    expect((await t.query(api.queries.reviews.get, { token: TOKEN, sessionId: "nope" })).review).toBeNull();
    await settle(t);
  });

  it("with AI off the jobs still store the rules version", async () => {
    await save(pushSession("p1", 5_000_000, 70));
    await settle(t);
    const r = await next();
    expect(r).toMatchObject({ stored: true });
    expect(r.plan.source).toBe("rules");
    expect(names(r.plan)).toEqual(["Bench press", "Dips"]);
  });
});

describe("AI path (mock provider)", () => {
  it("stores an AI plan, dashboard layout and review after the jobs ran", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await t.mutation(api.commands.goals.create, { token: TOKEN, goalId: "g1", title: "Train 3x", kind: "consistency", sessionsPerWeek: 3 });
    await save(pushSession("p1", Date.now() - 3_600_000));
    expect((await next()).plan.source).toBe("rules"); // not the AI version yet
    await settle(t);
    const r = await next();
    expect(r).toMatchObject({ stored: true });
    expect(r.plan.source).toBe("ai");
    expect(r.plan.rationale).toContain("Mock plan");
    const d = await t.query(api.queries.dashboard.get, { token: TOKEN, days: 30 });
    expect(d).toMatchObject({ stored: true, dashboard: { days: 30, source: "ai" } });
    expect(d.dashboard.modules.some((m) => m.type === "goal_progress")).toBe(true);
    expect(await t.query(api.queries.reviews.get, { token: TOKEN, sessionId: "p1" })).toMatchObject({ stored: true, review: { source: "ai" } });
  });

  it("does not delete the stored read models when facts change", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await save(pushSession("p1", 5_000_000));
    await settle(t);
    expect((await next()).plan.source).toBe("ai");
    await save(pushSession("p2", 6_000_000, 90));
    expect(await t.run((c) => c.db.query("plans").collect())).toHaveLength(1);
    expect(await next()).toMatchObject({ stored: true, plan: { source: "ai" } }); // still the old one, while the rebuild is pending
    await settle(t);
    const after = await next();
    expect(after.plan.exercises[0]!.sets[1]!.kg).toBe(90); // replaced by the rebuild (mock keeps the rules start)
  });
});

describe("plan safety limits and fallback (real provider code, stubbed network)", () => {
  it("caps weights at 1.25x the heaviest logged, plus exercise and set counts", async () => {
    stubOpenAi((job) =>
      job === "plan_session"
        ? JSON.stringify({
            rationale: "x",
            exercises: Array.from({ length: 15 }, (_, i) => ({ name: i === 0 ? "Bench press" : `Ex ${i}`, sets: Array.from({ length: 12 }, () => ({ reps: 5, kg: 200, max: false })) })),
          })
        : "{}",
    );
    await save(pushSession("p1", 5_000_000, 60));
    await settle(t);
    const { plan } = await next();
    expect(plan.source).toBe("ai");
    expect(plan.exercises).toHaveLength(12);
    expect(plan.exercises[0]!.sets).toHaveLength(10);
    expect(plan.exercises[0]!.sets[0]!.kg).toBe(75);
    expect(plan.exercises[1]!.sets[0]!.kg).toBe(200); // no history for that exercise
  });

  it("invalid AI output is retried once, then the code fallback is stored as source rules", async () => {
    const calls = stubOpenAi((job) => (job === "plan_session" ? "this is not json" : "{}"));
    await save(pushSession("p1", 5_000_000, 70));
    await settle(t);
    expect(calls.filter((c) => c.job === "plan_session" && c.input.focus === "Push")).toHaveLength(2);
    const { plan, stored } = await next();
    expect(stored).toBe(true);
    expect(plan.source).toBe("rules");
    expect(names(plan)).toEqual(["Bench press", "Dips"]);
  });

  it("valid JSON of the wrong shape also falls back", async () => {
    stubOpenAi((job) => (job === "plan_session" ? JSON.stringify({ rationale: "r", exercises: [{ name: "Bench", sets: [{ reps: 500, kg: 1, max: false }] }] }) : "{}"));
    await save(pushSession("p1", 5_000_000));
    await settle(t);
    expect((await next()).plan.source).toBe("rules");
  });

  it("a provider error falls back and does not fail the job", async () => {
    vi.stubEnv("AI_PROVIDER", "openai");
    vi.stubEnv("OPENAI_API_KEY", "k");
    vi.stubEnv("OPENAI_MODEL", "m");
    vi.stubGlobal("fetch", async () => new Response("boom", { status: 500 }));
    await save(pushSession("p1", 5_000_000));
    await settle(t);
    expect(await next()).toMatchObject({ stored: true, plan: { source: "rules" } });
  });

  it("missing key or model means AI off, fallbacks only", async () => {
    vi.stubEnv("AI_PROVIDER", "openai");
    vi.stubEnv("OPENAI_API_KEY", "");
    await save(pushSession("p1", 5_000_000));
    await settle(t);
    expect(await next()).toMatchObject({ stored: true, plan: { source: "rules" } });
  });
});
