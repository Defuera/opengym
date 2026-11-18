import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "../functions/_generated/api";
import { finalizeParsedGoal, parseGoalFallback } from "../functions/model/ai/jobs/parseGoal";
import { TOKEN, pushSession, setup, settle, stubOpenAi, type T } from "./helpers";

let t: T;
beforeEach(() => {
  vi.useFakeTimers();
  t = setup();
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

const create = (title: string, extra: Record<string, unknown> = {}) =>
  t.mutation(api.commands.goals.create, { token: TOKEN, goalId: "g1", title, kind: "custom", ...extra });
const goal = async () => (await t.query(api.queries.goals.list, { token: TOKEN }))[0]!;
const scheduled = () => t.run((c) => c.db.system.query("_scheduled_functions").collect());

describe("parse_goal", () => {
  it("create stores the text at once and schedules the job", async () => {
    await create("Bench press 70 kg by spring");
    expect(await goal()).toMatchObject({ title: "Bench press 70 kg by spring", kind: "custom", source: "user", status: "active" });
    const jobs = await scheduled();
    expect(jobs.some((j) => j.name.includes("parseGoal"))).toBe(true);
    await settle(t);
  });

  it("a resend of the same goalId does not schedule it again", async () => {
    await create("Bench 70 kg");
    await create("Bench 70 kg");
    expect((await scheduled()).filter((j) => j.name.includes("parseGoal"))).toHaveLength(1);
    await settle(t);
  });

  it("the AI output patches only the structure fields", async () => {
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: pushSession("p1", 5_000_000) });
    const calls = stubOpenAi(() => JSON.stringify({ kind: "strength", exercise: "bench PRESS", targetKg: 70 }));
    await create("Bench press 70 kg by spring");
    await settle(t);
    const g = await goal();
    expect(g).toMatchObject({ title: "Bench press 70 kg by spring", status: "active", source: "user", kind: "strength", exercise: "Bench press", targetKg: 70 });
    const parse = calls.filter((c) => c.job === "parse_goal");
    expect(parse).toHaveLength(1);
    expect(parse[0]!.input.exercises).toEqual(expect.arrayContaining(["Bench press", "Dips"]));
  });

  it("an exercise that is not in the log is dropped", async () => {
    stubOpenAi(() => JSON.stringify({ kind: "strength", exercise: "Zercher squat", targetKg: 100 }));
    await create("Zercher squat 100 kg");
    await settle(t);
    const g = await goal();
    expect(g.kind).toBe("strength");
    expect(g.exercise).toBeUndefined();
    expect(g.targetKg).toBe(100);
  });

  it("a stale title is not patched", async () => {
    stubOpenAi(() => JSON.stringify({ kind: "strength", targetKg: 70 }));
    await create("Bench 70 kg");
    // The user edits the title before the job runs.
    await t.run(async (c) => {
      const d = await c.db.query("goals").first();
      await c.db.patch(d!._id, { title: "Run a 10k" });
    });
    await settle(t);
    expect(await goal()).toMatchObject({ title: "Run a 10k", kind: "custom" });
    expect((await goal()).targetKg).toBeUndefined();
  });

  it("a goal removed before the job runs is not brought back", async () => {
    stubOpenAi(() => JSON.stringify({ kind: "strength", targetKg: 70 }));
    await create("Bench 70 kg");
    await t.mutation(api.commands.goals.remove, { token: TOKEN, goalId: "g1" });
    await settle(t);
    expect(await t.query(api.queries.goals.list, { token: TOKEN })).toEqual([]);
  });

  it("without AI the goal stays custom; the fallback reads kg and times a week", async () => {
    await create("Squat 120 kg, 3 times a week");
    await settle(t);
    expect(await goal()).toMatchObject({ kind: "custom", targetKg: 120, sessionsPerWeek: 3, title: "Squat 120 kg, 3 times a week" });
    await t.mutation(api.commands.goals.remove, { token: TOKEN, goalId: "g1" });
    await create("Get stronger");
    await settle(t);
    const g = await goal();
    expect(g).toMatchObject({ kind: "custom", title: "Get stronger" });
    expect(g.targetKg).toBeUndefined();
  });

  it("invalid AI output is rejected: the fallback is used", async () => {
    const calls = stubOpenAi(() => JSON.stringify({ kind: "banana", targetKg: -5 }));
    await create("Get stronger, 2 sessions a week");
    await settle(t);
    expect(calls.filter((c) => c.job === "parse_goal")).toHaveLength(2); // one retry
    expect(await goal()).toMatchObject({ kind: "custom", sessionsPerWeek: 2 });
  });

  it("a new title clears the old structure and is read again; same title does not", async () => {
    stubOpenAi((_j, input) => JSON.stringify(String(input.goal).includes("Squat") ? { kind: "strength", targetKg: 100 } : { kind: "strength", targetKg: 70 }));
    await create("Bench 70 kg");
    await settle(t);
    expect((await goal()).targetKg).toBe(70);
    await t.mutation(api.commands.goals.update, { token: TOKEN, goalId: "g1", status: "done" });
    expect((await goal()).targetKg).toBe(70);
    await t.mutation(api.commands.goals.update, { token: TOKEN, goalId: "g1", title: "Squat 100 kg" });
    expect(await goal()).toMatchObject({ title: "Squat 100 kg", kind: "custom", status: "done" });
    expect((await goal()).targetKg).toBeUndefined();
    await settle(t);
    expect(await goal()).toMatchObject({ title: "Squat 100 kg", kind: "strength", targetKg: 100, status: "done" });
  });
});

describe("parse_goal helpers", () => {
  it("fallback reads numbers only when they are there", () => {
    expect(parseGoalFallback("Bench 62,5 kg")).toEqual({ kind: "custom", targetKg: 62.5 });
    expect(parseGoalFallback("Train 4x a week")).toEqual({ kind: "custom", sessionsPerWeek: 4 });
    expect(parseGoalFallback("Feel fitter")).toEqual({ kind: "custom" });
  });
  it("finalize keeps the log's spelling", () => {
    expect(finalizeParsedGoal({ kind: "strength", exercise: " dips " }, ["Dips"]).exercise).toBe("Dips");
    expect(finalizeParsedGoal({ kind: "strength", exercise: "Curl" }, ["Dips"]).exercise).toBeUndefined();
  });
});
