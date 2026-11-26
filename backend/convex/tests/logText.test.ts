import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "../functions/_generated/api";
import { parseLogFallback, readKm, readMinutes } from "../functions/model/ai/jobs/parseLog";
import { shiftToDay } from "../functions/model/logDate";
import { TOKEN, pushSession, setup, settle, stubOpenAi, type T } from "./helpers";

const NOW = Date.UTC(2026, 10, 18, 15, 30); // Wednesday 18 Nov 2026
let t: T;
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

const log = (text: string, extra: Record<string, unknown> = {}) =>
  t.mutation(api.commands.sessions.logText, { token: TOKEN, sessionId: "l1", type: "Run", text, at: NOW, ...extra });
const stored = async () => (await t.query(api.queries.sessions.recent, { token: TOKEN }))[0]!;
const scheduled = () => t.run((c) => c.db.system.query("_scheduled_functions").collect());
const reviews = () => t.run((c) => c.db.query("reviews").collect());

describe("commands/sessions:logText", () => {
  it("stores the text at once as a fact and schedules the parse_log job", async () => {
    await log("45 min, 8 km, easy pace");
    expect(await stored()).toMatchObject({
      sessionId: "l1",
      kind: "activity",
      type: "Run",
      startedAt: NOW,
      endedAt: NOW,
      exercises: [],
      note: "45 min, 8 km, easy pace",
      source: "app",
      parse: "pending",
    });
    expect((await scheduled()).some((j) => j.name.includes("parseLog"))).toBe(true);
    await settle(t);
  });

  it("is idempotent by sessionId: a resend changes nothing and schedules nothing", async () => {
    await log("45 min");
    await log("something else entirely", { type: "Swim", at: NOW + 5 });
    expect((await t.query(api.queries.sessions.recent, { token: TOKEN })).length).toBe(1);
    expect(await stored()).toMatchObject({ type: "Run", note: "45 min" });
    expect((await scheduled()).filter((j) => j.name.includes("parseLog"))).toHaveLength(1);
    await settle(t);
  });

  it("rejects a bad token, a blank or long text, a blank or long type", async () => {
    await expect(log("x", { token: "nope" })).rejects.toThrow(/unauthorized/);
    await expect(log("")).rejects.toThrow();
    await expect(log("   ")).rejects.toThrow(/blank/);
    await expect(log("x".repeat(1001))).rejects.toThrow();
    await expect(log("ok", { type: "  " })).rejects.toThrow();
    await expect(log("ok", { type: "x".repeat(41) })).rejects.toThrow();
    await expect(log("ok", { sessionId: "" })).rejects.toThrow();
    expect(await t.query(api.queries.sessions.recent, { token: TOKEN })).toEqual([]);
    await log("x".repeat(1000));
    await settle(t);
  });
});

describe("parse_log job", () => {
  it("fills minutes, km and focus; the note and the activity name stay as they were", async () => {
    const calls = stubOpenAi(() => JSON.stringify({ minutes: 45, distanceKm: 8, focus: "Easy" }));
    await log("45 min, 8 km, easy pace");
    await settle(t);
    const s = await stored();
    expect(s).toMatchObject({ kind: "activity", type: "Run", minutes: 45, distanceKm: 8, focus: "Easy", note: "45 min, 8 km, easy pace", parse: "done", startedAt: NOW, endedAt: NOW });
    const parse = calls.filter((c) => c.job === "parse_log");
    expect(parse).toHaveLength(1);
    expect(parse[0]!.input).toMatchObject({ activity: "Run", text: "45 min, 8 km, easy pace", today: "2026-11-18 (Wednesday)" });
    expect(parse[0]!.input.exercisesTheUserKnows).toEqual([]);
  });

  it("sends the exercises of the log with their last sets", async () => {
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: pushSession("p1", NOW - 86_400_000) });
    const calls = stubOpenAi(() => "{}");
    await log("bench press");
    await settle(t);
    const known = calls.find((c) => c.job === "parse_log")!.input.exercisesTheUserKnows;
    expect(known).toEqual(expect.arrayContaining([expect.objectContaining({ name: "Bench press", lastSets: "6x40, 6x60, 1x60" })]));
  });

  it("exercises with given sets make it a gym session; time work inside is a time exercise", async () => {
    stubOpenAi((job) =>
      job === "review_session" ? JSON.stringify({ message: "Solid session." }) :
      JSON.stringify({
        minutes: 50,
        exercises: [
          { name: "Squat", sets: [{ reps: 5, kg: 100 }, { reps: 5, kg: 100 }] },
          { name: "Bike", measure: "time", sets: [{ minutes: 10 }] },
        ],
      }),
    );
    await log("squat 2x5 at 100, then 10 min on the bike");
    await settle(t);
    const s = await stored();
    expect(s).toMatchObject({ kind: "gym", type: "Run", minutes: 50, parse: "done", note: "squat 2x5 at 100, then 10 min on the bike" });
    expect(s.exercises).toEqual([
      { name: "Squat", sets: [{ reps: 5, kg: 100, max: false }, { reps: 5, kg: 100, max: false }] },
      { name: "Bike", measure: "time", sets: [{ minutes: 10 }] },
    ]);
    expect(await reviews()).toHaveLength(1); // the review is scheduled once the structure is written
  });

  it("an exercise reported without sets gets the usual sets from the log, with the log's spelling", async () => {
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: pushSession("p1", NOW - 2 * 86_400_000, 60) });
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: pushSession("p2", NOW - 86_400_000, 70) });
    stubOpenAi(() => JSON.stringify({ exercises: [{ name: "bench PRESS" }, { name: "Dips" }] }));
    await log("bench press and dips");
    await settle(t);
    const s = (await t.query(api.queries.sessions.recent, { token: TOKEN })).find((x) => x.sessionId === "l1")!;
    expect(s.kind).toBe("gym");
    expect(s.exercises).toEqual([
      { name: "Bench press", sets: [{ reps: 6, kg: 50, max: false }, { reps: 6, kg: 70, max: false }, { reps: 1, kg: 70, max: false }] }, // the last time, not the best
      { name: "Dips", sets: [{ reps: 10, kg: 0, max: false }] },
    ]);
    expect(s.note).toBe("bench press and dips");
  });

  it("an exercise that is not in the log and has no sets is left out; the session stays an activity", async () => {
    stubOpenAi(() => JSON.stringify({ minutes: 30, exercises: [{ name: "Zercher squat" }] }));
    await log("30 min of zercher squats");
    await settle(t);
    const s = await stored();
    expect(s).toMatchObject({ kind: "activity", exercises: [], minutes: 30, parse: "done", note: "30 min of zercher squats" });
  });

  it("an exercise that is not in the log but has sets is kept", async () => {
    stubOpenAi(() => JSON.stringify({ exercises: [{ name: "Zercher squat", sets: [{ reps: 8, kg: 40 }] }] }));
    await log("zercher squat 8 at 40");
    await settle(t);
    expect((await stored()).exercises).toEqual([{ name: "Zercher squat", sets: [{ reps: 8, kg: 40, max: false }] }]);
  });

  it('"yesterday" moves the session to that day and keeps the time of day', async () => {
    stubOpenAi(() => JSON.stringify({ minutes: 40, date: "2026-11-17" }));
    await log("yesterday 40 min");
    await settle(t);
    expect(await stored()).toMatchObject({ startedAt: NOW - 86_400_000, endedAt: NOW - 86_400_000, minutes: 40, note: "yesterday 40 min" });
  });

  it("a day in the future or not a date leaves the time as it was", async () => {
    stubOpenAi(() => JSON.stringify({ minutes: 40, date: "2026-11-25" }));
    await log("next week 40 min");
    await settle(t);
    expect(await stored()).toMatchObject({ startedAt: NOW, endedAt: NOW, minutes: 40 });
  });

  it("drops the result when the user edited the session before the job finished", async () => {
    stubOpenAi(() => JSON.stringify({ minutes: 45, distanceKm: 8 }));
    await log("45 min, 8 km");
    const edited = { sessionId: "l1", kind: "activity" as const, type: "Run", startedAt: NOW, endedAt: NOW, exercises: [], note: "ran with Sam", source: "app" as const };
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: edited });
    await settle(t);
    const s = await stored();
    expect(s).toMatchObject({ note: "ran with Sam" });
    expect(s.minutes).toBeUndefined();
    expect(s.distanceKm).toBeUndefined();
    expect(s.parse).toBeUndefined();
  });

  it("drops the result when the stored note is no longer the text that was read", async () => {
    stubOpenAi(() => JSON.stringify({ minutes: 45 }));
    await log("45 min");
    await t.run(async (c) => {
      const d = await c.db.query("sessions").first();
      await c.db.patch(d!._id, { note: "changed by hand" });
    });
    await settle(t);
    const s = await stored();
    expect(s.minutes).toBeUndefined();
    expect(s.parse).toBe("pending");
  });

  it("a session deleted before the job finished is not brought back", async () => {
    stubOpenAi(() => JSON.stringify({ minutes: 45 }));
    await log("45 min");
    await t.mutation(api.commands.sessions.remove, { token: TOKEN, sessionId: "l1" });
    await settle(t);
    expect(await t.query(api.queries.sessions.recent, { token: TOKEN })).toEqual([]);
  });

  it("without AI the fallback reads minutes and km with a regex", async () => {
    await log("Ran 1h10 today, 8 km");
    await settle(t);
    expect(await stored()).toMatchObject({ minutes: 70, distanceKm: 8, parse: "done", note: "Ran 1h10 today, 8 km", kind: "activity" });
  });

  it('without AI and with nothing to read, parse is "failed" and the note stays', async () => {
    await log("felt great");
    await settle(t);
    const s = await stored();
    expect(s).toMatchObject({ parse: "failed", note: "felt great", kind: "activity" });
    expect(s.minutes).toBeUndefined();
  });

  it("invalid AI output is rejected: one retry, then the fallback", async () => {
    const calls = stubOpenAi(() => JSON.stringify({ minutes: -5, exercises: "bench" }));
    await log("30 min, 5 km");
    await settle(t);
    expect(calls.filter((c) => c.job === "parse_log")).toHaveLength(2);
    expect(await stored()).toMatchObject({ minutes: 30, distanceKm: 5, parse: "done" });
  });

  it("the mock provider has a parse_log answer", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: pushSession("p1", NOW - 86_400_000) });
    await log("yesterday: 40 min easy, bench press");
    await settle(t);
    const s = (await t.query(api.queries.sessions.recent, { token: TOKEN })).find((x) => x.sessionId === "l1")!;
    expect(s).toMatchObject({ kind: "gym", minutes: 40, focus: "Easy", parse: "done", startedAt: NOW - 86_400_000 });
    expect(s.exercises[0]!.name).toBe("Bench press");
  });
});

describe("commands/sessions:save with parse", () => {
  const edited = (note: string) => ({ sessionId: "l1", kind: "activity" as const, type: "Run", startedAt: NOW, endedAt: NOW, exercises: [], note, source: "app" as const });

  it("accepts a session that carries parse and does not store it", async () => {
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: { ...edited("45 min"), parse: "pending" } });
    expect((await stored()).parse).toBeUndefined();
    await expect(t.mutation(api.commands.sessions.save, { token: TOKEN, session: { ...edited("x"), parse: "bogus" } as never })).rejects.toThrow();
  });

  it("a resend of an unchanged session keeps the pending parse; a real edit clears it", async () => {
    stubOpenAi(() => JSON.stringify({ minutes: 45 }));
    await log("45 min");
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: { ...edited("45 min"), parse: "pending" } });
    expect((await stored()).parse).toBe("pending");
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: edited("45 min, felt good") });
    expect((await stored()).parse).toBeUndefined();
    await settle(t);
    expect((await stored()).minutes).toBeUndefined();
  });
});

describe("parse_log helpers", () => {
  it("readMinutes", () => {
    expect(readMinutes("45 min")).toBe(45);
    expect(readMinutes("45mins easy")).toBe(45);
    expect(readMinutes("1h")).toBe(60);
    expect(readMinutes("1 hour")).toBe(60);
    expect(readMinutes("1.5 hours")).toBe(90);
    expect(readMinutes("1h30")).toBe(90);
    expect(readMinutes("1h 20 min")).toBe(80);
    expect(readMinutes("1:10")).toBe(70);
    expect(readMinutes("at 18:30 I ran")).toBeNull();
    expect(readMinutes("1h 5 km")).toBe(60);
    expect(readMinutes("felt great")).toBeNull();
    expect(readMinutes("900 min")).toBeNull();
  });
  it("readKm", () => {
    expect(readKm("8 km")).toBe(8);
    expect(readKm("8,5km")).toBe(8.5);
    expect(readKm("10 kilometres")).toBe(10);
    expect(readKm("8 kg")).toBeNull();
    expect(parseLogFallback("nothing")).toEqual({});
  });
  it("shiftToDay keeps the time of day across a change of summer time", () => {
    const at = Date.UTC(2026, 9, 26, 9, 0); // 26 Oct 2026, 10:00 in Berlin (winter time)
    expect(shiftToDay(at, "2026-10-24", Date.UTC(2026, 9, 27), "Europe/Berlin")).toBe(Date.UTC(2026, 9, 24, 8, 0)); // 10:00 in Berlin (summer time)
    expect(shiftToDay(at, "2026-02-31", Date.UTC(2026, 9, 27), "Europe/Berlin")).toBe(at);
    expect(shiftToDay(at, "2024-01-01", Date.UTC(2026, 9, 27), "Europe/Berlin")).toBe(at);
  });
});
