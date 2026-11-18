import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../functions/_generated/api";
import { normalizePredictions, normalizeSession } from "../functions/model/sessionShape";
import { fociByDue } from "../functions/model/rules/foci";
import { rulesPredictions } from "../functions/model/rules/predictions";
import { rulesPlan } from "../functions/model/rules/planner";
import { boundedPlanSessions } from "../functions/model/ai/jobs/inputs";
import type { Session } from "../functions/model/schema";
import { TOKEN, pushSession, setup, settle, stubOpenAi, type T } from "./helpers";

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
const recent = () => t.query(api.queries.sessions.recent, { token: TOKEN });
/** A row as the deployment holds it today: the flavour in `type`, no focus. */
const legacyRow = (sessionId: string, endedAt: number, type = "Upper", kind: "gym" | "activity" = "gym") => ({
  sessionId,
  kind,
  type,
  startedAt: endedAt - 3_600_000,
  endedAt,
  exercises: kind === "gym" ? [{ name: "Bench press", sets: [{ reps: 5, kg: 60, max: false }] }] : [],
  source: "app" as const,
});
const insertRaw = (rows: object[]) => t.run(async (c) => void (await Promise.all(rows.map((r) => c.db.insert("sessions", r as never)))));

describe("normalizing the old shape", () => {
  it("turns a gym type into focus; leaves activities and the new shape alone", () => {
    expect(normalizeSession({ kind: "gym", type: "Upper" })).toEqual({ kind: "gym", type: "Gym", focus: "Upper" });
    expect(normalizeSession({ kind: "gym", type: "gym" })).toEqual({ kind: "gym", type: "Gym" });
    expect(normalizeSession({ kind: "gym", type: "Gym", focus: "Legs" })).toEqual({ kind: "gym", type: "Gym", focus: "Legs" });
    expect(normalizeSession({ kind: "activity", type: "Run" })).toEqual({ kind: "activity", type: "Run" });
    expect(normalizeSession({ kind: "activity", type: "Run", focus: "Easy" })).toEqual({ kind: "activity", type: "Run", focus: "Easy" });
    const once = normalizeSession({ kind: "gym", type: "Push" });
    expect(normalizeSession(once)).toEqual(once);
  });

  it("predictions: legacy gym items become Gym items with a focus (at most 2 per activity)", () => {
    expect(
      normalizePredictions([
        { kind: "gym", type: "Pull", reason: "a" },
        { kind: "gym", type: "Legs", reason: "b" },
        { kind: "activity", type: "Run", reason: "c" },
      ]),
    ).toEqual([
      { kind: "gym", type: "Gym", focus: "Pull", reason: "a" },
      { kind: "gym", type: "Gym", focus: "Legs", reason: "b" },
      { kind: "activity", type: "Run", reason: "c" },
    ]);
  });
});

describe("commands/sessions:save", () => {
  it("stores focus for gym and for an activity, and reads it back", async () => {
    await save(pushSession("g", 2_000_000, 60, "Upper"));
    await save({ sessionId: "r", kind: "activity", type: "Run", focus: "Intervals", startedAt: 1, endedAt: 3_000_000, exercises: [], minutes: 30, source: "app" });
    const [run, gym] = await recent();
    expect(gym).toMatchObject({ kind: "gym", type: "Gym", focus: "Upper" });
    expect(run).toMatchObject({ kind: "activity", type: "Run", focus: "Intervals" });
  });

  it("normalises legacy input from an older app build or an old outbox entry", async () => {
    await save(legacyRow("old", 5_000_000, "Upper"));
    const stored = await t.run((c) => c.db.query("sessions").first());
    expect(stored).toMatchObject({ type: "Gym", focus: "Upper" });
    await save(legacyRow("old", 5_000_000, "Upper")); // a resend changes nothing
    expect(await t.run((c) => c.db.query("sessions").collect())).toHaveLength(1);
  });

  it("rejects a blank or too long type, a too long focus and an empty focus", async () => {
    await expect(save({ ...pushSession("a", 2_000_000), type: "   " })).rejects.toThrow(/type/);
    await expect(save({ ...pushSession("a", 2_000_000), type: "x".repeat(41) })).rejects.toThrow(/type/);
    await expect(save({ ...pushSession("a", 2_000_000), focus: "x".repeat(41) })).rejects.toThrow(/focus/);
    await expect(save({ ...pushSession("a", 2_000_000), focus: "" })).rejects.toThrow(/focus/);
    expect(await recent()).toEqual([]);
  });

  it("a saved session without focus is allowed (plain Gym)", async () => {
    const { focus, ...plain } = pushSession("a", 2_000_000);
    void focus;
    await save(plain);
    expect((await recent())[0]).toMatchObject({ type: "Gym" });
  });
});

describe("old rows before the migration has run", () => {
  it("validate on insert, and every read path shows them as Gym + focus", async () => {
    await insertRaw([legacyRow("a", 1_000_000, "Upper"), legacyRow("b", 2_000_000, "Legs"), legacyRow("c", 3_000_000, "Run", "activity")]);
    const rows = await t.query(api.queries.sessions.since, { token: TOKEN, since: 0 });
    expect(rows.map((r) => [r.type, r.focus])).toEqual([["Gym", "Upper"], ["Gym", "Legs"], ["Run", undefined]]);
    const plan = await t.query(api.queries.plans.next, { token: TOKEN, focus: "Upper" });
    expect(plan.plan).toMatchObject({ type: "Gym", focus: "Upper", id: "rules:Upper" });
    expect(plan.plan.exercises.map((e) => e.name)).toEqual(["Bench press"]);
    // the legacy argument name still works
    expect((await t.query(api.queries.plans.next, { token: TOKEN, type: "Upper" })).plan.focus).toBe("Upper");
  });

  it("a legacy plan row (type, no focus) and a legacy predictions row still validate; the plan row is read as the new shape", async () => {
    await t.run(async (c) => {
      await c.db.insert("plans", { type: "Upper", version: 1, createdAt: 1, source: "ai", rationale: "old", exercises: [] });
      await c.db.insert("predictions", { version: 1, createdAt: 1, source: "ai", items: [{ kind: "gym", type: "Legs", reason: "r" }, { kind: "activity", type: "Run", reason: "x" }] });
    });
    // the old predictions row stays in the table (never read now); the advised focus comes from the log
    expect((await t.query(api.queries.plans.next, { token: TOKEN })).plan.type).toBe("Gym");
  });
});

describe("jobs/migrations:activityFirst", () => {
  const run = (args: { cursor?: string | null; batch?: number } = {}) => t.mutation(internal.jobs.migrations.activityFirst, args);
  const sessions = () => t.run((c) => c.db.query("sessions").collect());

  async function seed() {
    await insertRaw([
      legacyRow("a", 1_000_000, "Upper"),
      legacyRow("b", 2_000_000, "Legs"),
      legacyRow("c", 3_000_000, "Run", "activity"),
      { ...legacyRow("d", 4_000_000, "Gym"), focus: "Push" }, // already new
    ]);
    await t.run(async (c) => {
      await c.db.insert("plans", { type: "Upper", version: 1, createdAt: 1, source: "ai", rationale: "u", exercises: [] });
      await c.db.insert("plans", { type: "Legs", version: 1, createdAt: 1, source: "ai", rationale: "l-old", exercises: [] });
      await c.db.insert("plans", { focus: "Legs", version: 9, createdAt: 9, source: "ai", rationale: "l-new", exercises: [] });
      await c.db.insert("predictions", { version: 1, createdAt: 1, source: "ai", items: [{ kind: "gym", type: "Upper", reason: "r" }, { kind: "gym", type: "Legs", reason: "r" }, { kind: "activity", type: "Run", reason: "x" }] });
      await c.db.insert("dashboards", { days: 7, version: 1, createdAt: 1, source: "ai", modules: [{ type: "consistency" }] });
      await c.db.insert("reviews", { sessionId: "a", version: 1, createdAt: 1, source: "rules", summary: "Upper: 1 exercises, 1 sets.", changes: [] });
    });
  }

  it("moves the gym flavour to focus, leaves activities and new rows, fixes the read models", async () => {
    await seed();
    expect(await run()).toEqual({ sessions: 2, plans: 2, predictions: 1, done: true });
    const byId = Object.fromEntries((await sessions()).map((s) => [s.sessionId, s]));
    expect(byId.a).toMatchObject({ type: "Gym", focus: "Upper" });
    expect(byId.b).toMatchObject({ type: "Gym", focus: "Legs" });
    expect(byId.c).toMatchObject({ type: "Run" });
    expect(byId.c!.focus).toBeUndefined();
    expect(byId.d).toMatchObject({ type: "Gym", focus: "Push" });
    // exercises and times are not touched
    expect(byId.a!.exercises).toHaveLength(1);
    expect(byId.a!.endedAt).toBe(1_000_000);

    const plans = await t.run((c) => c.db.query("plans").collect());
    expect(plans.map((p) => [p.focus, p.type, p.rationale]).sort()).toEqual([["Legs", undefined, "l-new"], ["Upper", undefined, "u"]]);
    const pred = await t.run((c) => c.db.query("predictions").first());
    expect(pred!.items).toEqual([{ kind: "gym", type: "Gym", focus: "Upper", reason: "r" }, { kind: "gym", type: "Gym", focus: "Legs", reason: "r" }, { kind: "activity", type: "Run", reason: "x" }]);
    expect(await t.run((c) => c.db.query("dashboards").collect())).toHaveLength(1);
    expect(await t.run((c) => c.db.query("reviews").collect())).toHaveLength(1);
    await settle(t); // the rebuild it asked for runs with the AI off
  });

  it("running twice changes nothing the second time and does not ask for a rebuild", async () => {
    await seed();
    await run();
    await settle(t);
    const before = { s: await sessions(), p: await t.run((c) => c.db.query("plans").collect()), r: await t.run((c) => c.db.query("rebuilds").first()) };
    expect(await run()).toEqual({ sessions: 0, plans: 0, predictions: 0, done: true });
    expect(await sessions()).toEqual(before.s);
    expect(await t.run((c) => c.db.query("plans").collect())).toEqual(before.p);
    expect(await t.run((c) => c.db.query("rebuilds").first())).toEqual(before.r);
  });

  it("works in batches: it schedules itself page by page and ends with the read models", async () => {
    await seed();
    expect(await run({ batch: 1 })).toMatchObject({ done: false });
    await settle(t);
    expect((await sessions()).every((s) => s.kind === "activity" || (s.type === "Gym" && s.focus))).toBe(true);
    const plans = await t.run((c) => c.db.query("plans").collect());
    expect(plans.every((p) => p.focus !== undefined && p.type === undefined)).toBe(true);
    expect((await t.run((c) => c.db.query("predictions").first()))!.items[0]).toMatchObject({ type: "Gym" });
  });

  it("an empty deployment is a no-op", async () => {
    expect(await run()).toEqual({ sessions: 0, plans: 0, predictions: 0, done: true });
    expect(await t.run((c) => c.db.query("rebuilds").first())).toBeNull();
  });

  it("marks facts changed so the read models are rebuilt in the new shape", async () => {
    await seed();
    await run();
    await settle(t);
    const plans = await t.run((c) => c.db.query("plans").collect());
    expect(plans.every((p) => p.focus !== undefined)).toBe(true);
    expect(plans.map((p) => p.focus).sort()).toEqual(["Legs", "Upper"]); // the set-based items of the rules ranking (Gym Upper, Gym Legs); not every focus
  });
});

describe("predictions: activities, not gym flavours", () => {
  const s = (id: string, daysAgo: number, kind: "gym" | "activity", type: string, focus?: string): Session => ({
    id,
    kind,
    type,
    ...(focus ? { focus } : {}),
    startedAt: NOW - daysAgo * DAY - 3_600_000,
    endedAt: NOW - daysAgo * DAY,
    exercises: kind === "gym" ? [{ name: "Squat", sets: [{ reps: 5, kg: 80, max: false }] }] : [],
    source: "app",
  });

  it("Gym comes with the focus that is due and a short reason; a second Gym item only because the log has a second focus", () => {
    const log = [s("1", 6, "gym", "Gym", "Upper"), s("2", 2, "gym", "Gym", "Legs")];
    const p = rulesPredictions(log, NOW);
    expect(p[0]).toEqual({ kind: "gym", type: "Gym", focus: "Upper", reason: "Last legs session was 2 days ago" }); // only logged foci; Upper is due
    expect(p[1]).toMatchObject({ kind: "gym", type: "Gym", focus: "Legs" });
    expect(p).toHaveLength(2);
    expect(p[0]!.reason.length).toBeLessThanOrEqual(80);
    expect(rulesPredictions([s("1", 6, "gym", "Gym", "Upper")], NOW)).toHaveLength(1); // one focus: one item
  });

  it("the focus longest ago wins once all are logged", () => {
    const log = [s("1", 9, "gym", "Gym", "Push"), s("2", 8, "gym", "Gym", "Pull"), s("3", 7, "gym", "Gym", "Legs"), s("4", 1, "gym", "Gym", "Upper")];
    expect(rulesPredictions(log, NOW)[0]).toMatchObject({ focus: "Push", reason: "Last upper session was yesterday" });
  });

  it("Run gets an advised session type only when the log has one", () => {
    const none = rulesPredictions([s("1", 3, "activity", "Run")], NOW);
    expect(none).toEqual([{ kind: "activity", type: "Run", reason: "Done 1 time" }]);
    const some = rulesPredictions([s("1", 9, "activity", "Run", "Long"), s("2", 5, "activity", "Run", "Easy"), s("3", 2, "activity", "Run", "Easy")], NOW);
    expect(some[0]).toMatchObject({ type: "Run", focus: "Long", reason: "Done 3 times" });
  });

  it("the foci of an activity are exactly the logged ones, done longest ago first; there are no starter foci", () => {
    const log = [s("1", 6, "gym", "Gym", "Upper"), s("2", 2, "gym", "Gym", "Legs"), s("3", 1, "gym", "Home", "Quick")];
    expect(fociByDue(log, "Gym")).toEqual(["Upper", "Legs"]);
    expect(fociByDue(log, "home")).toEqual(["Quick"]);
    expect(fociByDue([], "Gym")).toEqual([]);
    expect(fociByDue([s("3", 1, "activity", "Run", "Easy")], "Gym")).toEqual([]);
  });

  it("with no history there are no predictions", () => {
    expect(rulesPredictions([], NOW)).toEqual([]);
  });
});

describe("plans per focus", () => {
  it("rules plan and the bounded AI input work per activity and focus", () => {
    const g = (id: string, focus: string, at: number, ex: string): Session => ({ id, kind: "gym", type: "Gym", focus, startedAt: at, endedAt: at, exercises: [{ name: ex, sets: [{ reps: 5, kg: 50, max: false }] }], source: "app" });
    const all = [g("1", "Upper", 1, "Bench press"), g("2", "Legs", 2, "Squat"), g("3", "Upper", 3, "Row")];
    expect(rulesPlan(all, "Gym", "Upper").exercises.map((e) => e.name)).toEqual(["Row"]);
    expect(rulesPlan(all, "gym", "legs").rationale).toBe("Repeats your last gym legs session with the same sets.");
    expect(rulesPlan(all, "Gym", "Pull").exercises).toEqual([]); // no Pull history: empty, no starter
    expect(rulesPlan(all, "Home").exercises).toEqual([]);
    const many = Array.from({ length: 30 }, (_, i) => g(`s${i}`, i % 3 === 0 ? "Upper" : "Legs", i + 1, "X"));
    const got = boundedPlanSessions(many, "Gym", "Upper");
    expect(got.length).toBeLessThanOrEqual(12);
    expect(got.filter((x) => x.focus === "Upper").length).toBeGreaterThanOrEqual(6);
  });

  it("next with no focus returns the plan of the advised focus; the jobs store plans only for the ranked items", async () => {
    await save(pushSession("p1", NOW - 3 * DAY, 60, "Upper"));
    await save(pushSession("p2", NOW - 2 * DAY, 60, "Legs"));
    await save(pushSession("p3", NOW - DAY, 60, "Pull"));
    await settle(t);
    const plans = await t.run((c) => c.db.query("plans").collect());
    expect(plans.map((p) => p.focus).sort()).toEqual(["Legs", "Upper"]); // Gym Upper and Gym Legs are the 2 items; Pull is built on read
    expect(plans.every((p) => p.type === undefined && p.activityKey === "gym")).toBe(true);
    expect(await t.query(api.queries.plans.next, { token: TOKEN })).toMatchObject({ stored: true, plan: { type: "Gym", focus: "Upper" } });
    expect(await t.query(api.queries.plans.next, { token: TOKEN, focus: "Upper" })).toMatchObject({ stored: true, plan: { focus: "Upper" } });
    expect(await t.query(api.queries.plans.next, { token: TOKEN, focus: "Pull" })).toMatchObject({ stored: false, plan: { focus: "Pull", source: "rules" } });
  });

  it("switching focus never calls the AI", async () => {
    const calls = stubOpenAi(() => "{}");
    await save(pushSession("p1", NOW - DAY, 60, "Upper"));
    await settle(t);
    const n = calls.length;
    await t.query(api.queries.plans.next, { token: TOKEN, focus: "Upper" });
    await t.query(api.queries.plans.next, { token: TOKEN, focus: "Legs" });
    await t.query(api.queries.plans.next, { token: TOKEN });
    expect(calls.length).toBe(n);
  });
});

describe("imports accept the old shape", () => {
  it("loadStructured normalises kind gym with type Upper and keeps a given focus", async () => {
    const gym = (type: string, focus?: string) => ({ kind: "gym", type, ...(focus ? { focus } : {}), startedAt: 1_000_000, endedAt: 4_600_000, exercises: [{ name: "Bench press", sets: [{ reps: 5, kg: 60, max: false }] }] });
    await t.mutation(api.commands.imports.loadStructured, {
      token: TOKEN,
      sessions: [{ ...gym("Upper"), id: "old" }, { ...gym("Gym", "Legs"), id: "new" }, { kind: "activity", type: "Run", focus: "Easy", startedAt: 1, endedAt: 2, id: "run" }],
    });
    const rows = await t.query(api.queries.sessions.since, { token: TOKEN, since: 0 });
    const by = Object.fromEntries(rows.map((r) => [r.sessionId, r]));
    expect(by.old).toMatchObject({ type: "Gym", focus: "Upper" });
    expect(by.new).toMatchObject({ type: "Gym", focus: "Legs" });
    expect(by.run).toMatchObject({ type: "Run", focus: "Easy" });
    expect((await t.run((c) => c.db.query("sessions").collect())).find((r) => r.sessionId === "old")).toMatchObject({ type: "Gym", focus: "Upper" });
  });

  it("the AI import job accepts both shapes", async () => {
    // covered end to end in filesImport.test.ts (mock answers the new shape); here the old shape through the draft mapper
    const { draftToSession } = await import("../functions/model/importUnits");
    const notes = new Set<string>();
    const d = (type: string, focus?: string) => ({ kind: "gym" as const, type, ...(focus ? { focus } : {}), exercises: [{ name: "Squat", sets: [{ reps: 5, kg: 80, max: false }] }], date: "2026-01-02" });
    expect(draftToSession(d("Upper"), { name: "f", createdAt: 0 }, "i", () => "id1", notes)).toMatchObject({ type: "Gym", focus: "Upper" });
    expect(draftToSession(d("Gym", "Legs"), { name: "f", createdAt: 0 }, "i", () => "id2", notes)).toMatchObject({ type: "Gym", focus: "Legs" });
  });
});

describe("reviews and context use the new shape", () => {
  it("a review compares the same activity and focus and names it", async () => {
    await save(pushSession("a", NOW - 3 * DAY, 60, "Upper"));
    await save(pushSession("b", NOW - 2 * DAY, 60, "Legs"));
    await save(pushSession("c", NOW - DAY, 70, "Upper"));
    const r = await t.query(api.queries.reviews.get, { token: TOKEN, sessionId: "c" });
    expect(r.review!.summary).toContain("Gym (Upper)");
    expect(r.review!.changes.join(" ")).toContain("Bench press: top set 70 kg (was 60 kg)");
    const first = await t.query(api.queries.reviews.get, { token: TOKEN, sessionId: "b" });
    expect(first.review!.summary).toContain("First session of this kind");
    await settle(t);
  });

  it("the dashboard shows Gym with the focus as a tag, and the chat/log prompt carries focus", async () => {
    await save(pushSession("a", Date.now() - 3_600_000, 60, "Upper"));
    const { dashboard } = await t.query(api.queries.dashboard.get, { token: TOKEN, days: 7 });
    const recentMod = dashboard.modules.find((m) => m.type === "recent_sessions");
    expect(recentMod).toMatchObject({ items: [{ title: "Gym", subtitle: "Upper · 2 exercises, 4 sets" }] });
    const { logForPrompt } = await import("../functions/model/ai/jobs/shared");
    const [{ id, ...rest }] = [pushSession("z", 5_000_000, 60, "Upper")].map(({ sessionId, ...r }) => ({ id: sessionId, ...r }));
    void id;
    expect(logForPrompt([{ id: "z", ...rest }])[0]).toMatchObject({ type: "Gym", focus: "Upper" });
    await settle(t);
  });
});
