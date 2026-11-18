import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../functions/_generated/api";
import { START_REQUEST_TTL_MS } from "../functions/lib/constants";
import { buildSessionJob } from "../functions/model/ai/jobs/buildSession";
import { coachPicture } from "../functions/model/ai/jobs/coachPicture";
import { fallbackProposal, nameFromText } from "../functions/model/startFallback";
import { planSessionJob } from "../functions/model/ai/jobs/planSession";
import { buildPlanInput } from "../functions/model/ai/jobs/inputs";
import { rulesPredictions } from "../functions/model/rules/predictions";
import type { Session } from "../functions/model/schema";
import { SessionSchema } from "../functions/model/schema";
import { activityKey, normalizeSession } from "../functions/model/sessionShape";
import { TOKEN, pushSession, setsSession, setup, settle, stubOpenAi, type T } from "./helpers";

let t: T;
const NOW = Date.UTC(2026, 10, 17, 12);
const DAY = 86_400_000;
beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
  t = setup();
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

const save = (s: unknown) => t.mutation(api.commands.sessions.save, { token: TOKEN, session: s as never });
const stored = () => t.run((c) => c.db.query("sessions").collect());
const request = (requestId: string, text: string) => t.mutation(api.commands.start.request, { token: TOKEN, requestId, text });
const requestNamed = (requestId: string, name?: string, text?: string) => t.mutation(api.commands.start.request, { token: TOKEN, requestId, ...(name !== undefined ? { name } : {}), ...(text !== undefined ? { text } : {}) });
const getRequest = (requestId: string) => t.query(api.queries.start.request, { token: TOKEN, requestId });
const planNext = (args: { activity?: string; focus?: string; type?: string } = {}) => t.query(api.queries.plans.next, { token: TOKEN, ...args });
const names = (p: { exercises: { name: string }[] }) => p.exercises.map((e) => e.name);

/** Model-side session (id, not sessionId). */
const model = (id: string, daysAgo: number, type: string, focus?: string, kind: "gym" | "activity" = "gym"): Session => ({
  id,
  kind,
  type,
  ...(focus ? { focus } : {}),
  startedAt: NOW - daysAgo * DAY - 1_800_000,
  endedAt: NOW - daysAgo * DAY,
  exercises: kind === "gym" ? [{ name: "Push-up", sets: [{ reps: 10, kg: 0, max: false }] }] : [],
  source: "app",
});

describe("activityKey", () => {
  it("is lower case, trimmed, inner whitespace collapsed", () => {
    expect(activityKey("  Home   Workout ")).toBe("home workout");
    expect(activityKey("HOME")).toBe(activityKey("home"));
    expect(activityKey("")).toBe("");
  });
});

describe("a session with sets may have any activity name", () => {
  it("SessionSchema accepts type Home for kind gym, with or without focus", () => {
    const base = { id: "a", kind: "gym" as const, type: "Home", startedAt: 1, endedAt: 2, exercises: [{ name: "Push-up", sets: [{ reps: 10, kg: 0, max: false }] }], source: "app" as const };
    expect(SessionSchema.safeParse(base).success).toBe(true);
    expect(SessionSchema.safeParse({ ...base, focus: "Quick" }).success).toBe(true);
    expect(SessionSchema.safeParse({ ...base, type: "x".repeat(41) }).success).toBe(false);
    expect(SessionSchema.safeParse({ ...base, type: "  " }).success).toBe(false);
    expect(SessionSchema.safeParse({ ...base, kind: "activity" }).success).toBe(false); // time/distance has no exercises
  });

  it("save stores Home as it is (trimmed), reads it back, and a resend changes nothing", async () => {
    const s = setsSession("h1", 5_000_000, "  Home ", "Quick");
    await save(s);
    await save(s);
    const rows = await stored();
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ kind: "gym", type: "Home", focus: "Quick" });
    expect((await t.query(api.queries.sessions.recent, { token: TOKEN }))[0]).toMatchObject({ type: "Home", focus: "Quick" });
  });

  it("type may be left out and is then Gym; for a time or distance session it is required", async () => {
    const { type, ...noType } = setsSession("h2", 5_000_000);
    void type;
    await save(noType);
    expect((await stored())[0]).toMatchObject({ kind: "gym", type: "Gym" });
    await expect(save({ sessionId: "r", kind: "activity", startedAt: 1, endedAt: 2, exercises: [], source: "app" })).rejects.toThrow(/type/);
  });

  it("old rows and old outbox payloads still read as before", async () => {
    await save({ ...setsSession("old", 5_000_000, "Upper") }); // old payload: flavour in type, no focus
    await save(pushSession("new", 6_000_000, 60, "Legs"));
    await save({ ...setsSession("home-no-focus", 7_000_000, "Home") }); // not mistaken for an old flavour
    const by = Object.fromEntries((await stored()).map((r) => [r.sessionId, r]));
    expect(by.old).toMatchObject({ type: "Gym", focus: "Upper" });
    expect(by.new).toMatchObject({ type: "Gym", focus: "Legs" });
    expect(by["home-no-focus"]).toMatchObject({ type: "Home" });
    expect(by["home-no-focus"]!.focus).toBeUndefined();
    // a row stored before the change, read raw
    await t.run((c) => c.db.insert("sessions", { sessionId: "raw", kind: "gym", type: "Pull", startedAt: 1, endedAt: 8_000_000, exercises: [], source: "app" }));
    expect((await t.query(api.queries.sessions.since, { token: TOKEN, since: 7_500_000 }))[0]).toMatchObject({ type: "Gym", focus: "Pull" });
    expect(normalizeSession({ kind: "gym", type: "Home", focus: "Quick" })).toEqual({ kind: "gym", type: "Home", focus: "Quick" });
    expect(normalizeSession({ kind: "gym", type: "Upper", focus: "Heavy" })).toEqual({ kind: "gym", type: "Upper", focus: "Heavy" }); // a focus is given: an activity named Upper
  });
});

describe("predictions with several set-based activities", () => {
  it("ranks Gym and Home and Run together, every name from the log, at most 2 per activity and 6 in total", () => {
    const log = [
      model("1", 9, "Gym", "Upper"),
      model("2", 8, "Gym", "Legs"),
      model("3", 7, "Gym", "Pull"),
      model("4", 6, "Home", "Quick"),
      model("5", 5, "Home", "Long"),
      model("6", 4, "Home", "Core"),
      model("7", 3, "Run", undefined, "activity"),
      model("8", 2, "Swim", undefined, "activity"),
      model("9", 1, "Yoga", undefined, "activity"),
    ];
    const p = rulesPredictions(log, NOW);
    expect(p.length).toBeLessThanOrEqual(6);
    const count = (type: string) => p.filter((x) => x.type === type).length;
    expect(p).toHaveLength(6); // 5 activities, one item each, then the one second item that fits
    expect(Math.max(count("Gym"), count("Home"), count("Run"))).toBeLessThanOrEqual(2);
    expect(count("Gym") + count("Home")).toBe(3);
    expect(p.filter((x) => x.kind === "gym").every((x) => x.focus)).toBe(true);
    expect(new Set(p.map((x) => x.type))).toEqual(new Set(["Gym", "Home", "Run", "Swim", "Yoga"]));
    expect(p.every((x) => x.reason.length <= 80)).toBe(true);
    // first items of every activity come before second items
    expect(p.slice(0, 5).map((x) => x.type).sort()).toEqual(["Gym", "Home", "Run", "Swim", "Yoga"]);
  });

  it("the name is the log's most recent spelling, and Home alone has one item when it has one focus", () => {
    const log = [model("1", 5, "home", "Quick"), model("2", 1, "Home", "Quick")];
    expect(rulesPredictions(log, NOW)).toEqual([{ kind: "gym", type: "Home", focus: "Quick", reason: "Last quick session was yesterday" }]);
  });
});


describe("plans by activity and focus", () => {
  it("are stored per activity + focus, only for the set-based ranked items (max 3)", async () => {
    await save(pushSession("g1", NOW - 4 * DAY, 60, "Upper"));
    await save(pushSession("g2", NOW - 3 * DAY, 60, "Legs"));
    await save(setsSession("h1", NOW - 2 * DAY, "Home", "Quick"));
    await save(setsSession("h2", NOW - DAY, "Home", "Long"));
    await save({ sessionId: "r1", kind: "activity", type: "Run", startedAt: 1, endedAt: NOW - 5 * DAY, exercises: [], minutes: 30, source: "app" });
    await settle(t);
    const plans = await t.run((c) => c.db.query("plans").collect());
    expect(plans.length).toBeLessThanOrEqual(3);
    expect(plans.length).toBe(3);
    expect(plans.every((p) => p.activityKey !== undefined && p.focusKey !== undefined)).toBe(true);
    expect(plans.some((p) => p.activityKey === "run")).toBe(false);
    const preds = rulesPredictions(await t.run((c) => c.db.query("sessions").collect().then((rows) => rows.map((r) => normalizeSession(r as never) as never))) as never, NOW).filter((p) => p.kind === "gym").slice(0, 3);
    for (const p of preds) expect(await planNext({ activity: p.type, focus: p.focus })).toMatchObject({ stored: true, plan: { type: p.type, focus: p.focus } });
  });

  it("next({activity}) reads the plan of that activity; the old args still work", async () => {
    await save(pushSession("g", NOW - 2 * DAY, 60, "Upper"));
    await save(setsSession("h", NOW - DAY, "Home", "Quick", [{ name: "Squat jump", sets: [{ reps: 15, kg: 0, max: false }] }]));
    await settle(t);
    const home = await planNext({ activity: "home" });
    expect(home).toMatchObject({ stored: true, plan: { type: "Home", focus: "Quick" } });
    expect(names(home.plan)).toEqual(["Squat jump"]);
    expect((await planNext({ activity: "Gym", focus: "Upper" })).plan).toMatchObject({ type: "Gym", focus: "Upper" });
    expect((await planNext({ focus: "Upper" })).plan.type).toBe("Gym"); // old args: focus only
    expect((await planNext({ type: "Upper" })).plan).toMatchObject({ type: "Gym", focus: "Upper" }); // old args: legacy type
    expect((await planNext()).plan.type).toBe("Gym"); // default activity
  });

  it("a plan for an activity that is not predicted is built by the rules fallback from its own last session", async () => {
    await save(setsSession("h", NOW - DAY, "Home", "Quick", [{ name: "Squat jump", sets: [{ reps: 15, kg: 0, max: false }] }]));
    const r = await planNext({ activity: "Home", focus: "Quick" });
    expect(r).toMatchObject({ stored: false, plan: { source: "rules", type: "Home", focus: "Quick" } });
    expect(names(r.plan)).toEqual(["Squat jump"]);
    expect(r.plan.exercises[0]!.sets).toEqual([{ reps: 15, kg: 0, max: false }]);
  });

  it("with no session of the activity the fallback is an EMPTY plan (no starter template, no Gym borrowed)", async () => {
    await save(pushSession("g", NOW - DAY, 60, "Upper"));
    const r = await planNext({ activity: "Padel" });
    expect(r).toMatchObject({ stored: false, plan: { type: "Padel", source: "rules", exercises: [] } });
    expect(r.plan.focus).toBeUndefined();
    expect((await planNext({ activity: "Gym", focus: "Legs" })).plan.exercises).toEqual([]);
  });

  it("limits still apply to the rules fallback and to the stored plan", async () => {
    await t.mutation(api.commands.limits.save, { token: TOKEN, limit: { limitId: "k", part: "left_knee", title: "Left knee", status: "active", rules: [{ kind: "avoid", text: "No jumps", exercises: ["squat jump"] }] } });
    await save(setsSession("h", NOW - DAY, "Home", "Quick", [{ name: "Squat jump", sets: [{ reps: 15, kg: 0, max: false }] }, { name: "Push-up", sets: [{ reps: 10, kg: 0, max: false }] }]));
    await settle(t);
    expect(names((await planNext({ activity: "Home", focus: "Quick" })).plan)).toEqual(["Push-up"]);
  });

  it("the plan prompt speaks of a session with sets for the activity, no gym, and carries notes and limits", async () => {
    const log = [model("1", 2, "Home", "Quick")];
    const note = { id: "c1", text: "Only a pair of 10 kg dumbbells at home", topic: "equipment", active: true, source: "user" as const, createdAt: 1 };
    const limits = [{ limitId: "k", part: "left_knee" as const, title: "Left knee", status: "active" as const, rules: [{ kind: "avoid" as const, text: "No jumps" }] }];
    const p = planSessionJob.build(buildPlanInput(log, [], [note], "Home", "Quick", limits));
    const whole = `${p.system}\n${p.messages.map((m) => m.content).join("\n")}`;
    expect(p.messages[0]!.content).toContain("Plan the next session with sets for Home, focus Quick.");
    expect(p.system).toContain("a session with sets");
    expect(p.system.toLowerCase()).not.toContain("gym session");
    expect(whole).toContain("Only a pair of 10 kg dumbbells at home");
    expect(whole).toContain("No jumps");
    const data = JSON.parse(p.messages[0]!.content.split("INPUT_JSON:\n")[1]!);
    expect(data).toMatchObject({ activity: "Home", focus: "Quick" });
  });

  it("plan rows from before this change are read as Gym plans, and the next rebuild replaces and prunes them", async () => {
    await save(pushSession("g", NOW - DAY, 60, "Upper"));
    await t.run(async (c) => {
      await c.db.insert("plans", { focus: "Upper", version: 1, createdAt: 1, source: "ai", rationale: "old upper", exercises: [] });
      await c.db.insert("plans", { focus: "Pull", version: 1, createdAt: 1, source: "ai", rationale: "old pull", exercises: [] });
    });
    expect(await planNext({ focus: "Upper" })).toMatchObject({ stored: true, plan: { rationale: "old upper" } });
    await settle(t);
    const plans = await t.run((c) => c.db.query("plans").collect());
    expect(plans.map((p) => p.rationale)).toEqual([expect.not.stringContaining("old")]);
    expect(plans[0]).toMatchObject({ activityKey: "gym", focusKey: "upper" });
  });
});

describe("start request", () => {
  it("is stored pending and the query shows it; unknown ids give null", async () => {
    expect(await request("r1", " quick home session, 15 min ")).toBe("r1");
    expect(await getRequest("r1")).toEqual({ requestId: "r1", status: "pending" });
    expect(await getRequest("nope")).toBeNull();
    expect((await t.run((c) => c.db.query("startRequests").first()))).toMatchObject({ text: "quick home session, 15 min", status: "pending" });
    await settle(t);
  });

  it("validates text 1..200 and the token", async () => {
    await expect(request("r", "")).rejects.toThrow(/text/);
    await expect(request("r", "   ")).rejects.toThrow(/text/);
    await expect(request("r", "x".repeat(201))).rejects.toThrow(/text/);
    await expect(request("", "ok")).rejects.toThrow(/requestId/);
    await expect(t.mutation(api.commands.start.request, { token: "bad", requestId: "r", text: "ok" })).rejects.toThrow();
    await expect(t.query(api.queries.start.request, { token: "bad", requestId: "r" })).rejects.toThrow();
    await request("ok", "x".repeat(200));
    await settle(t);
  });

  it("is idempotent by requestId: a resend stores nothing new and runs the job once", async () => {
    const calls = stubOpenAi(() => JSON.stringify({ kind: "gym", type: "Home", plan: { rationale: "r", exercises: [{ name: "Glute Bridge", sets: [{ reps: 12, kg: 0, max: false }] }] } }));
    await request("r1", "home");
    await request("r1", "home");
    await request("r1", "something else entirely"); // same id: the first text stays
    await settle(t);
    expect(await t.run((c) => c.db.query("startRequests").collect())).toHaveLength(1);
    expect(calls.filter((c) => c.job === "build_session")).toHaveLength(1);
    expect((await t.run((c) => c.db.query("startRequests").first()))!.text).toBe("home");
    const done = await getRequest("r1");
    await request("r1", "home"); // a resend after it is ready does not reset it
    expect(await getRequest("r1")).toEqual(done);
    await settle(t);
  });

  it("an empty plan from the AI is invalid: one retry, then the plain-code fallback", async () => {
    const calls = stubOpenAi(() => JSON.stringify({ kind: "gym", type: "Home", plan: { rationale: "r", exercises: [] } }));
    await request("r1", "home workout");
    await settle(t);
    expect(calls.filter((c) => c.job === "build_session")).toHaveLength(2);
    expect((await getRequest("r1"))!.status).toBe("ready");
  });

  it("AI off: ready at once with the fallback, a session with sets named from the text and an empty plan", async () => {
    await request("r1", "padel doubles, 60 min, with Sam");
    await settle(t);
    const r = await getRequest("r1");
    expect(r).toMatchObject({ requestId: "r1", status: "ready", proposal: { kind: "gym", type: "Padel doubles", plan: { type: "Padel doubles", source: "rules", exercises: [] } } });
    expect(r!.proposal!.plan!.id).toBe("start:r1");
  });

  it("the fallback reuses a known name by activityKey", async () => {
    await save(setsSession("h", NOW - DAY, "Home Workout", "Quick"));
    await request("r1", "home   workout, 20 min");
    await settle(t);
    expect(await getRequest("r1")).toMatchObject({ status: "ready", proposal: { kind: "gym", type: "Home Workout" } });
    expect(nameFromText("  hotel gym, 30 min")).toBe("Hotel gym");
    expect(nameFromText(",abc")).toBe(",abc");
    expect(nameFromText("x".repeat(60))).toHaveLength(40);
    expect(fallbackProposal({ text: "run", known: [{ type: "Run", kind: "activity", foci: [] }] })).toMatchObject({ kind: "gym", type: "Run", plan: { exercises: [] } });
  });

  it("AI path: the proposal is stored with a plan in the plans:next shape; the name reuses the log's spelling; minutes and focus are kept", async () => {
    await save(setsSession("h", NOW - DAY, "Home", "Quick", [{ name: "Push-up", sets: [{ reps: 10, kg: 0, max: false }] }]));
    const calls = stubOpenAi((job) =>
      job === "build_session"
        ? JSON.stringify({ kind: "gym", type: "HOME", focus: "Short", minutes: 15, reason: "Fits 15 min", plan: { rationale: "Short home session", exercises: [{ name: "Push-up", sets: [{ reps: 10, kg: 0, max: false }] }, { name: "Squat", sets: [{ reps: 15, kg: 0, max: false }] }] } })
        : "{}",
    );
    await request("r1", "quick home session, 15 min");
    await settle(t);
    const input = calls.find((c) => c.job === "build_session")!.input;
    expect(input).toMatchObject({ activity: null, request: "quick home session, 15 min", noteForToday: null });
    expect(input.exercisesTheUserKnows[0]).toMatchObject({ name: "Push-up" });
    expect(input.recentSessions).toHaveLength(1);
    const r = await getRequest("r1");
    expect(r).toMatchObject({
      status: "ready",
      proposal: { kind: "gym", type: "Home", focus: "Short", minutes: 15, reason: "Fits 15 min", plan: { id: "start:r1", type: "Home", focus: "Short", source: "ai", rationale: "Short home session" } },
    });
    expect(names(r!.proposal!.plan!)).toEqual(["Push-up", "Squat"]);
    expect(typeof r!.proposal!.plan!.createdAt).toBe("number");
  });

  it("the plan is checked in code: weight cap from the full history, the size for the minutes asked, and the avoid rules", async () => {
    await t.mutation(api.commands.limits.save, { token: TOKEN, limit: { limitId: "k", part: "left_knee", title: "Left knee", status: "active", rules: [{ kind: "avoid", text: "No jumps", exercises: ["Squat jump"] }] } });
    await save(setsSession("h", NOW - DAY, "Home", undefined, [{ name: "Goblet squat", sets: [{ reps: 10, kg: 10, max: false }] }]));
    stubOpenAi((job) =>
      job === "build_session"
        ? JSON.stringify({ kind: "gym", type: "Home", minutes: 10, plan: { rationale: "r", exercises: [{ name: "Goblet squat", sets: Array.from({ length: 6 }, () => ({ reps: 10, kg: 100, max: false })) }, { name: "Push-up", sets: Array.from({ length: 6 }, () => ({ reps: 10, kg: 0, max: false })) }] } })
        : "{}",
    );
    await request("r1", "home 10 min");
    await settle(t);
    const plan = (await getRequest("r1"))!.proposal!.plan!;
    expect(plan.exercises.reduce((n, e) => n + e.sets.length, 0)).toBe(5); // 10 min: max(4, 5) sets
    expect(plan.exercises[0]!.sets.every((s) => s.kg === 12.5)).toBe(true); // 1.25 x the heaviest logged (10)
  });

  it("a plan with an avoided exercise is retried, then the fallback is stored (ready, empty plan)", async () => {
    await t.mutation(api.commands.limits.save, { token: TOKEN, limit: { limitId: "k", part: "left_knee", title: "Left knee", status: "active", rules: [{ kind: "avoid", text: "No jumps", exercises: ["Squat jump"] }] } });
    const calls = stubOpenAi((job) => (job === "build_session" ? JSON.stringify({ kind: "gym", type: "Home", plan: { rationale: "r", exercises: [{ name: "Squat jump", sets: [{ reps: 10, kg: 0, max: false }] }] } }) : "{}"));
    await request("r1", "home");
    await settle(t);
    expect(calls.filter((c) => c.job === "build_session")).toHaveLength(2);
    expect(await getRequest("r1")).toMatchObject({ status: "ready", proposal: { type: "Home", plan: { source: "rules", exercises: [] } } });
  });

  it("a proposal that is not a session with exercises is invalid: retried, then the fallback", async () => {
    const calls = stubOpenAi((job) => (job === "build_session" ? JSON.stringify({ kind: "activity", type: "Run", minutes: 30 }) : "{}"));
    await request("r1", "run 30 min");
    await settle(t);
    expect(calls.filter((c) => c.job === "build_session")).toHaveLength(2);
    expect(await getRequest("r1")).toMatchObject({ status: "ready", proposal: { kind: "gym", type: "Run 30 min", plan: { source: "rules", exercises: [] } } });
    vi.unstubAllGlobals();
    stubOpenAi((job) => (job === "build_session" ? JSON.stringify({ kind: "gym", type: "Home" }) : "{}"));
    await request("r2", "home");
    await settle(t);
    expect(await getRequest("r2")).toMatchObject({ status: "ready", proposal: { kind: "gym", type: "Home", plan: { source: "rules", exercises: [] } } });
  });

  it("a time exercise from the coach is kept in a session of kind gym", async () => {
    stubOpenAi((job) => (job === "build_session" ? JSON.stringify({ kind: "gym", type: "Run", minutes: 30, plan: { rationale: "r", exercises: [{ name: "Easy run", measure: "time", sets: [{ minutes: 30 }] }] } }) : "{}"));
    await request("r1", "run 30 min");
    await settle(t);
    const r = await getRequest("r1");
    expect(r).toMatchObject({ status: "ready", proposal: { kind: "gym", type: "Run", plan: { source: "ai", exercises: [{ name: "Easy run", measure: "time" }] } } });
  });

  it("the coach's name is trimmed; a name that is empty or over 40 falls back to the text", async () => {
    const plan = { rationale: "r", exercises: [{ name: "Squat", sets: [{ reps: 10, kg: 0, max: false }] }] };
    stubOpenAi((job) => (job === "build_session" ? JSON.stringify({ kind: "gym", type: "  Hotel gym  ", plan }) : "{}"));
    await request("r1", "something long");
    await settle(t);
    expect((await getRequest("r1"))!.proposal!.type).toBe("Hotel gym");
    vi.unstubAllGlobals();
    stubOpenAi((job) => (job === "build_session" ? JSON.stringify({ kind: "gym", type: " ", plan }) : "{}"));
    await request("r2", "hotel gym, 30 min");
    await settle(t);
    expect((await getRequest("r2"))!.proposal!.type).toBe("Hotel gym");
    vi.unstubAllGlobals();
    stubOpenAi((job) => (job === "build_session" ? JSON.stringify({ kind: "gym", type: "a".repeat(41), plan }) : "{}"));
    await request("r3", "boxing, 30 min");
    await settle(t);
    expect(await getRequest("r3")).toMatchObject({ proposal: { type: "Boxing", plan: { source: "rules" } } });
  });

  it("AI failure (garbage, a provider error): retried once, then ready with the fallback; never stuck pending", async () => {
    const calls = stubOpenAi((job) => (job === "build_session" ? "this is not json" : "{}"));
    await request("r1", "boxing, 30 min");
    await settle(t);
    expect(calls.filter((c) => c.job === "build_session")).toHaveLength(2);
    expect(await getRequest("r1")).toMatchObject({ status: "ready", proposal: { kind: "gym", type: "Boxing", plan: { source: "rules", exercises: [] } } });
    vi.unstubAllGlobals();
    vi.stubEnv("AI_PROVIDER", "openai");
    vi.stubEnv("OPENAI_API_KEY", "k");
    vi.stubEnv("OPENAI_MODEL", "m");
    vi.stubGlobal("fetch", async () => new Response("boom", { status: 500 }));
    await request("r2", "swim");
    await settle(t);
    expect(await getRequest("r2")).toMatchObject({ status: "ready", proposal: { type: "Swim" } });
  });

  it("an unexpected error marks the request failed; a late result does not change a finished request", async () => {
    await request("r1", "home");
    await t.mutation(internal.jobs.startRequest.save, { requestId: "r1", failed: true });
    expect(await getRequest("r1")).toEqual({ requestId: "r1", status: "failed" });
    await t.mutation(internal.jobs.startRequest.save, { requestId: "r1", source: "ai", proposal: { kind: "gym", type: "Late", plan: { rationale: "r", exercises: [] } } });
    expect(await getRequest("r1")).toEqual({ requestId: "r1", status: "failed" });
    await settle(t);
    expect(await getRequest("r1")).toEqual({ requestId: "r1", status: "failed" }); // the job sees it is not pending
  });

  it("requests older than a day are removed by the next request", async () => {
    await request("old", "a");
    await settle(t);
    vi.setSystemTime(NOW + START_REQUEST_TTL_MS + 1_000);
    await request("new", "b");
    expect(await getRequest("old")).toBeNull();
    expect(await getRequest("new")).toMatchObject({ status: "pending" });
    await settle(t);
  });

  it("mock provider answers the job end to end", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await save(setsSession("h", NOW - DAY, "Home", "Quick"));
    await request("r1", "home, 20 min");
    await settle(t);
    expect(await getRequest("r1")).toMatchObject({ status: "ready", proposal: { kind: "gym", type: "Home", plan: { source: "ai" } } });
  });

  it("does not ask for a rebuild and writes no fact", async () => {
    await request("r1", "home");
    await settle(t);
    expect(await t.run((c) => c.db.query("rebuilds").first())).toBeNull();
    expect(await stored()).toEqual([]);
  });
});

describe("start request with a name", () => {
  const plan = (n: string) => ({ rationale: "r", exercises: [{ name: n, sets: [{ reps: 10, kg: 0, max: false }] }] });

  it("name only: stored, the job gets name and an empty wish, the type is the name", async () => {
    const calls = stubOpenAi((job) => (job === "build_session" ? JSON.stringify({ kind: "gym", type: "Home", plan: plan("Squat") }) : "{}"));
    await requestNamed("n1", " Hotel gym ");
    expect(await t.run((c) => c.db.query("startRequests").first())).toMatchObject({ name: "Hotel gym", status: "pending" });
    await settle(t);
    expect(calls.find((c) => c.job === "build_session")!.input).toMatchObject({ activity: "Hotel gym", noteForToday: null });
    expect(await getRequest("n1")).toMatchObject({ status: "ready", proposal: { kind: "gym", type: "Hotel gym" } });
  });

  it("name + text: both stored and sent as separate inputs; the known spelling is kept", async () => {
    await save(setsSession("h", NOW - DAY, "Gym", "Upper", [{ name: "Bench press", sets: [{ reps: 8, kg: 60, max: false }] }]));
    const calls = stubOpenAi((job) => (job === "build_session" ? JSON.stringify({ kind: "gym", type: "Gym", minutes: 20, plan: plan("Bench press") }) : "{}"));
    await requestNamed("n2", "GYM", "only 20 minutes, no bench");
    expect(await t.run((c) => c.db.query("startRequests").first())).toMatchObject({ name: "GYM", text: "only 20 minutes, no bench" });
    await settle(t);
    const input = calls.find((c) => c.job === "build_session")!.input;
    expect(input).toMatchObject({ activity: "GYM", noteForToday: "only 20 minutes, no bench" });
    expect(input.exercisesTheUserKnows[0]).toMatchObject({ name: "Bench press", lastSets: "8x60", bestKg: 60 });
    expect(await getRequest("n2")).toMatchObject({ status: "ready", proposal: { type: "Gym", minutes: 20 } });
  });

  it("the name forces the type even when the AI answers another type", async () => {
    stubOpenAi((job) => (job === "build_session" ? JSON.stringify({ kind: "gym", type: "Upper body day", plan: plan("Push-up") }) : "{}"));
    await requestNamed("n3", "Home", "quick");
    await settle(t);
    expect(await getRequest("n3")).toMatchObject({ status: "ready", proposal: { type: "Home", plan: { type: "Home", source: "ai" } } });
  });

  it("the plain-code fallback uses the name as typed (not cut at a comma)", async () => {
    await requestNamed("n4", "Hotel, floor 2", "x");
    await settle(t);
    expect(await getRequest("n4")).toMatchObject({ status: "ready", proposal: { kind: "gym", type: "Hotel, floor 2", plan: { source: "rules", exercises: [] } } });
    expect(fallbackProposal({ text: "", name: "home", known: [{ type: "Home", kind: "gym", foci: [] }] })).toMatchObject({ type: "Home" });
  });

  it("validates: one of name or text is required; name 1..40; old text-only still works", async () => {
    await expect(requestNamed("v1")).rejects.toThrow(/text/);
    await expect(requestNamed("v2", "  ")).rejects.toThrow(/name/);
    await expect(requestNamed("v3", "x".repeat(41))).rejects.toThrow(/name/);
    await expect(requestNamed("v4", "Home", "x".repeat(201))).rejects.toThrow(/text/);
    await requestNamed("v5", "x".repeat(40));
    await requestNamed("v6", undefined, "home");
    expect(await t.run((c) => c.db.query("startRequests").collect())).toHaveLength(2);
    await settle(t);
  });

  it("old text-only request: unchanged input and no name stored", async () => {
    const calls = stubOpenAi((job) => (job === "build_session" ? JSON.stringify({ kind: "gym", type: "Boxing", plan: plan("Jab") }) : "{}"));
    await request("o1", "boxing, 30 min");
    await settle(t);
    const input = calls.find((c) => c.job === "build_session")!.input;
    expect(input).toMatchObject({ request: "boxing, 30 min" });
    expect(input.name).toBeUndefined();
    expect((await t.run((c) => c.db.query("startRequests").first()))!.name).toBeUndefined();
    expect(await getRequest("o1")).toMatchObject({ proposal: { type: "Boxing" } });
  });
});

describe("start request with a fixed name and a note (the coach decides the focus)", () => {
  const plan = (n: string) => ({ rationale: "r", exercises: [{ name: n, sets: [{ reps: 10, kg: 0, max: false }] }] });
  const seed = () => save(setsSession("h", NOW - 3 * DAY, "Gym", "Legs", [{ name: "Squat", sets: [{ reps: 5, kg: 100, max: false }] }]));

  it("the removed today mode is no longer an argument", async () => {
    await expect(t.mutation(api.commands.start.request, { token: TOKEN, requestId: "t1", mode: "today" } as never)).rejects.toThrow();
    await expect(t.mutation(api.commands.start.request, { token: TOKEN, requestId: "t2", name: "Gym", hintType: "Gym" } as never)).rejects.toThrow();
    await expect(requestNamed("t3", "Gym")).resolves.toBe("t3");
    await settle(t);
  });

  it("the job input has the name, the note, the time and the last sessions; the type stays the name", async () => {
    await seed();
    const calls = stubOpenAi((job) => (job === "build_session" ? JSON.stringify({ kind: "gym", type: "Other", focus: "Upper", plan: plan("Bench press") }) : "{}"));
    await t.mutation(api.commands.start.request, { token: TOKEN, requestId: "t1", name: "Gym", text: "left hand is sore" });
    await settle(t);
    const input = calls.find((c) => c.job === "build_session")!.input;
    expect(input).toMatchObject({ activity: "Gym", noteForToday: "left hand is sore" });
    expect(input.recentSessions).toBeDefined();
    expect(input.last4Weeks).toHaveLength(4);
    expect(input.timeNow).toBeDefined();
    expect(await getRequest("t1")).toMatchObject({ status: "ready", proposal: { type: "Gym", focus: "Upper", plan: { source: "ai" } } });
  });

  it("the fallback is the named activity with an empty plan", () => {
    expect(fallbackProposal({ text: "", known: [], name: "Home" })).toMatchObject({ type: "Home", plan: { exercises: [] } });
  });

  it("the prompt has the one naming sentence and the input carries activity and request", () => {
    const picture = coachPicture([], [], [], [], [], NOW);
    const named = buildSessionJob.build({ name: "Gym", note: "x", picture, limits: [] });
    const free = buildSessionJob.build({ name: null, note: "", request: "quick home session", picture, limits: [] });
    expect(free.system).toContain("when activity is null, name it from the request (one to three words), and reuse a name from the person's log when the request means the same activity.");
    expect(free.system).toBe(named.system);
    expect(JSON.parse(free.messages[0]!.content.split("INPUT_JSON:\n")[1]!)).toMatchObject({ activity: null, request: "quick home session", noteForToday: null });
    expect(JSON.parse(named.messages[0]!.content.split("INPUT_JSON:\n")[1]!)).not.toHaveProperty("request");
  });
});
