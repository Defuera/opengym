import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../functions/_generated/api";
import crons from "../functions/crons";
import { DELETE_AFTER_MS, PURGE_BATCH } from "../functions/lib/constants";
import { TOKEN, pushSession, setup, settle, type T } from "./helpers";

/** ADR-020: remove marks, every read hides, a cron erases after 72 hours, the operator can restore. */
const NOW = Date.UTC(2026, 10, 17, 12);
const HOUR = 3_600_000;
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

const saveS = (s: ReturnType<typeof pushSession>) => t.mutation(api.commands.sessions.save, { token: TOKEN, session: s });
const removeS = (sessionId: string) => t.mutation(api.commands.sessions.remove, { token: TOKEN, sessionId });
const sessionRows = () => t.run((c) => c.db.query("sessions").collect());
const reviewRows = () => t.run((c) => c.db.query("reviews").collect());
const entryRows = () => t.run((c) => c.db.query("entries").collect());
const fileRows = () => t.run((c) => c.db.query("files").collect());
const purge = () => t.mutation(internal.jobs.purge.run, {});
const q = <A extends Record<string, unknown>>(fn: any, args: A = {} as A) => t.query(fn, { token: TOKEN, ...args }); // eslint-disable-line @typescript-eslint/no-explicit-any

async function upload(fileId: string) {
  const storageId = await t.run((c) => c.storage.store(new Blob(["x"], { type: "image/jpeg" })));
  await t.mutation(api.commands.files.register, { token: TOKEN, fileId, storageId, name: "a.jpg", mime: "image/jpeg", size: 1 });
  return storageId;
}
const entry = (entryId: string, over: Record<string, unknown> = {}) => ({ entryId, text: "Lunch", fileIds: [] as string[], at: NOW - HOUR, createdAt: NOW - HOUR, ...over });
const saveE = (e: ReturnType<typeof entry>) => t.mutation(api.commands.entries.save, { token: TOKEN, entry: e });
const removeE = (entryId: string) => t.mutation(api.commands.entries.remove, { token: TOKEN, entryId });
const legs = (id: string, endedAt: number) => ({ ...pushSession(id, endedAt), focus: "Legs", exercises: [{ name: "Leg Press", sets: [{ reps: 8, kg: 100, max: false }] }] });

describe("session remove marks", () => {
  it("sets deletedAt, keeps the row and the review, and is idempotent", async () => {
    await saveS(pushSession("s1", NOW - 2 * HOUR));
    await settle(t);
    expect(await reviewRows()).toHaveLength(1);
    expect(await removeS("s1")).toBe(true);
    const first = (await sessionRows())[0]!.deletedAt;
    expect(first).toBeGreaterThanOrEqual(NOW);
    vi.setSystemTime(NOW + HOUR);
    expect(await removeS("s1")).toBe(false);
    expect((await sessionRows())[0]!.deletedAt).toBe(first);
    expect(await reviewRows()).toHaveLength(1);
    expect(await removeS("unknown")).toBe(false);
    await settle(t);
  });

  it("asks for a rebuild, so read models forget the session", async () => {
    await saveS(pushSession("s1", NOW - 2 * HOUR));
    await settle(t);
    const runs = (await t.run((c) => c.db.query("rebuilds").first()))!.runs;
    await removeS("s1");
    await settle(t);
    expect((await t.run((c) => c.db.query("rebuilds").first()))!.runs).toBe(runs + 1);
  });
});

describe("a marked session is invisible", () => {
  it("to recent, since, load, review, plan, dashboard, about me and ask-after", async () => {
    const emptyAbout = await q(api.queries.aboutMe.get);
    const emptyDash = await q(api.queries.dashboard.get, { days: 7 });
    await t.mutation(api.commands.limits.save, { token: TOKEN, limit: { limitId: "k1", part: "left_knee", title: "Knee", status: "active", rules: [] } });
    const emptyAboutWithLimit = await q(api.queries.aboutMe.get);
    await saveS(legs("s1", NOW - 2 * HOUR));
    await settle(t);
    await t.mutation(api.commands.limits.checkin, { token: TOKEN, checkinId: "c1", limitId: "k1", sessionId: "s1", at: NOW, feeling: "ok" } as never).catch(() => undefined);
    const livePlan = await q(api.queries.plans.next, { activity: "Gym", focus: "Legs" });
    expect(livePlan.plan.exercises.length).toBeGreaterThan(0);
    expect((await q(api.queries.aboutMe.get)).load.d14.quads).toBeGreaterThan(0);
    await removeS("s1");
    await settle(t);

    expect(await q(api.queries.sessions.recent)).toEqual([]);
    expect(await q(api.queries.sessions.since, { since: 0 })).toEqual([]);
    expect(await q(api.queries.sessions.load, { sessionId: "s1" })).toBeNull();
    expect(await q(api.queries.reviews.get, { sessionId: "s1" })).toEqual({ review: null, stored: false });
    expect((await q(api.queries.plans.next, { activity: "Gym", focus: "Legs" })).plan.exercises).toEqual([]);
    expect(await q(api.queries.dashboard.get, { days: 7 })).toMatchObject({ dashboard: { modules: emptyDash.dashboard.modules } });
    const about = await q(api.queries.aboutMe.get);
    expect(about.load).toEqual(emptyAbout.load);
    expect(about.limits.every((l: { checkins: { sessionLabel?: string }[] }) => l.checkins.every((c) => c.sessionLabel === undefined))).toBe(true);
    expect(about.limits).toHaveLength(emptyAboutWithLimit.limits.length);
    expect(await q(api.queries.aboutMe.askAfter, { sessionId: "s1" })).toEqual([]);
  });

  it("recent keeps its count: the limit is applied to live rows", async () => {
    for (const [id, h] of [["a", 5], ["b", 4], ["c", 3], ["d", 2]] as const) await saveS(pushSession(id, NOW - h * HOUR));
    await removeS("d");
    await removeS("c");
    expect((await q(api.queries.sessions.recent, { limit: 2 })).map((s: { sessionId: string }) => s.sessionId)).toEqual(["b", "a"]);
    await settle(t);
  });

  it("is left out of the coach picture, the chat context and a job's whole history", async () => {
    await saveS(legs("s1", NOW - 2 * HOUR));
    await saveS(legs("s2", NOW - 3 * HOUR));
    await removeS("s1");
    const seen = await t.run(async (ctx) => {
      const { allSessions } = await import("../functions/lib/db");
      const { coachPicture } = await import("../functions/model/ai/jobs/coachPicture");
      const all = await allSessions(ctx, "owner");
      const picture = coachPicture(all, [], [], [], [], NOW);
      return { ids: all.map((s) => s.id), picture: JSON.stringify(picture) };
    });
    expect(seen.ids).toEqual(["s2"]);
    await removeS("s2");
    const none = await t.run(async (ctx) => {
      const { allSessions } = await import("../functions/lib/db");
      const { coachPicture } = await import("../functions/model/ai/jobs/coachPicture");
      return { all: await allSessions(ctx, "owner"), picture: coachPicture(await allSessions(ctx, "owner"), [], [], [], [], NOW) };
    });
    expect(none.all).toEqual([]);
    expect(none.picture.exercisesTheUserKnows).toEqual([]);
    await settle(t);
  });
});

describe("a late write does not bring a marked row back", () => {
  it("save and logText for a marked session change nothing and return the id", async () => {
    await saveS(pushSession("s1", NOW - 2 * HOUR));
    await t.mutation(api.commands.sessions.logText, { token: TOKEN, sessionId: "l1", type: "Run", text: "ran 5k", at: NOW - HOUR });
    await removeS("s1");
    await removeS("l1");
    await settle(t);
    const before = JSON.stringify(await sessionRows());
    expect(await saveS(pushSession("s1", NOW - 2 * HOUR))).toBe("s1");
    expect(await saveS({ ...pushSession("s1", NOW - 2 * HOUR), note: "changed" })).toBe("s1");
    expect(await t.mutation(api.commands.sessions.logText, { token: TOKEN, sessionId: "l1", type: "Run", text: "ran 5k", at: NOW - HOUR })).toBe("l1");
    await settle(t);
    expect(JSON.stringify(await sessionRows())).toBe(before);
    expect(await q(api.queries.sessions.recent)).toEqual([]);
  });

  it("a note save for a marked entry changes nothing", async () => {
    await saveE(entry("e1"));
    await removeE("e1");
    const before = JSON.stringify(await entryRows());
    expect(await saveE(entry("e1", { text: "edited" }))).toBe("e1");
    expect(JSON.stringify(await entryRows())).toBe(before);
    expect(await q(api.queries.entries.recent)).toEqual([]);
  });

  it("a pending parse_log result and a review for a marked session are dropped", async () => {
    await t.mutation(api.commands.sessions.logText, { token: TOKEN, sessionId: "l1", type: "Run", text: "ran 5k", at: NOW - HOUR });
    await saveS(pushSession("s1", NOW - 2 * HOUR));
    await removeS("l1");
    await removeS("s1");
    await settle(t); // the jobs scheduled by the writes run now
    expect((await sessionRows()).find((s) => s.sessionId === "l1")!.parse).toBe("pending");
    await t.mutation(internal.jobs.parseLog.save, { userId: "owner", sessionId: "l1", text: "ran 5k", parse: "done", minutes: 30 });
    expect((await sessionRows()).find((s) => s.sessionId === "l1")).toMatchObject({ parse: "pending" });
    expect((await sessionRows()).find((s) => s.sessionId === "l1")!.minutes).toBeUndefined();
    expect(await t.query(internal.jobs.parseLog.input, { userId: "owner", sessionId: "l1", text: "ran 5k" })).toBeNull();
    expect(await reviewRows()).toHaveLength(0);
    await t.mutation(internal.jobs.reviews.save, { userId: "owner", sessionId: "s1", version: 1, source: "rules", summary: "x", changes: [] });
    expect(await reviewRows()).toHaveLength(0);
    expect(await t.query(internal.jobs.reviews.input, { userId: "owner", sessionId: "s1" })).toBeNull();
  });

  it("an import does not bring a marked session back", async () => {
    await saveS(pushSession("s1", NOW - 2 * HOUR));
    await removeS("s1");
    await t.run(async (ctx) => {
      const { writeImportItems } = await import("../functions/lib/importWrite");
      const rest = pushSession("s1", NOW - 2 * HOUR);
      await writeImportItems(ctx, "owner", { sessions: [{ ...rest, source: "import", importId: "i1" }], goals: [], context: [] });
    });
    await settle(t);
    expect((await sessionRows()).filter((s) => s.sessionId === "s1")).toHaveLength(1);
    expect((await sessionRows())[0]!.source).toBe("app");
    expect(await q(api.queries.sessions.recent)).toEqual([]);
  });
});

describe("a marked note is invisible", () => {
  it("to the list and to the coach (entries and images), and keeps its files for now", async () => {
    await upload("f1");
    await saveE(entry("e1", { fileIds: ["f1"] }));
    await saveE(entry("e2", { at: NOW - 2 * HOUR }));
    const coach = () =>
      t.run(async (ctx) => {
        const { coachEntries, entryImageFiles } = await import("../functions/lib/entriesDb");
        return { entries: (await coachEntries(ctx, "owner", NOW)).map((e) => e.id), images: (await entryImageFiles(ctx, "owner", NOW)).map((f) => f.fileId) };
      });
    expect(await coach()).toEqual({ entries: ["e2", "e1"], images: ["f1"] });
    expect(await removeE("e1")).toBe(true);
    expect(await coach()).toEqual({ entries: ["e2"], images: [] });
    expect((await q(api.queries.entries.recent)).map((e: { entryId: string }) => e.entryId)).toEqual(["e2"]);
    expect((await q(api.queries.entries.recent, { limit: 1 })).map((e: { entryId: string }) => e.entryId)).toEqual(["e2"]);
    expect(await fileRows()).toHaveLength(1);
  });
});

describe("purge", () => {
  it("erases only rows marked more than 72 hours ago, with the review and the files", async () => {
    await saveS(pushSession("old", NOW - 90 * HOUR));
    await saveS(pushSession("young", NOW - 80 * HOUR));
    await saveS(pushSession("live", NOW - 2 * HOUR));
    await settle(t);
    expect(await reviewRows()).toHaveLength(3);
    const blob = await upload("f-old");
    await upload("f-young");
    await saveE(entry("e-old", { fileIds: ["f-old"] }));
    await saveE(entry("e-young", { fileIds: ["f-young"] }));
    await saveE(entry("e-live"));
    const T0 = Date.now(); // the test clock of a transaction never goes back, so time only moves forward from here
    await removeS("old");
    await removeE("e-old");
    vi.setSystemTime(T0 + 40 * HOUR);
    await removeS("young");
    await removeE("e-young");
    vi.setSystemTime(T0 + DELETE_AFTER_MS + HOUR); // old is 73 h marked, young 33 h
    expect(await purge()).toEqual({ sessions: 1, entries: 1, programs: 0, aiCalls: 0 });
    expect((await sessionRows()).map((s) => s.sessionId).sort()).toEqual(["live", "young"]);
    expect((await reviewRows()).map((r) => r.sessionId).sort()).toEqual(["live", "young"]);
    expect((await entryRows()).map((e) => e.entryId).sort()).toEqual(["e-live", "e-young"]);
    expect((await fileRows()).map((f) => f.fileId)).toEqual(["f-young"]);
    expect(await t.run((c) => c.storage.get(blob))).toBeNull();
    vi.setSystemTime(T0 + 40 * HOUR + DELETE_AFTER_MS + HOUR);
    expect(await purge()).toEqual({ sessions: 1, entries: 1, programs: 0, aiCalls: 0 });
    expect((await sessionRows()).map((s) => s.sessionId)).toEqual(["live"]);
    expect(await fileRows()).toHaveLength(0);
  });

  it("works in bounded batches and schedules itself again when a batch is full", async () => {
    await t.run(async (ctx) => {
      for (let i = 0; i < PURGE_BATCH + 5; i++) {
        await ctx.db.insert("entries", { userId: "owner", entryId: `e${i}`, text: "x", fileIds: [], at: NOW, createdAt: NOW, deletedAt: 1 });
      }
    });
    expect(await purge()).toEqual({ sessions: 0, entries: PURGE_BATCH, programs: 0, aiCalls: 0 });
    expect(await entryRows()).toHaveLength(5);
    await settle(t);
    expect(await entryRows()).toHaveLength(0);
  });

  it("is registered as an hourly cron", () => {
    const job = (crons as unknown as { crons: Record<string, { schedule: unknown }> }).crons["purge deleted"];
    expect(job?.schedule).toEqual({ type: "interval", hours: 1 });
  });
});

describe("restore", () => {
  it("brings a marked session back, and asks for a rebuild", async () => {
    await saveS(pushSession("s1", NOW - 2 * HOUR));
    await settle(t);
    await removeS("s1");
    await settle(t);
    const runs = (await t.run((c) => c.db.query("rebuilds").first()))!.runs;
    expect(await t.mutation(internal.commands.sessions.restoreSession, { userId: "owner", sessionId: "s1" })).toBe(true);
    expect((await q(api.queries.sessions.recent)).map((s: { sessionId: string }) => s.sessionId)).toEqual(["s1"]);
    expect((await q(api.queries.reviews.get, { sessionId: "s1" })).stored).toBe(true);
    expect("deletedAt" in (await sessionRows())[0]!).toBe(false);
    await settle(t);
    expect((await t.run((c) => c.db.query("rebuilds").first()))!.runs).toBe(runs + 1);
    expect(await t.mutation(internal.commands.sessions.restoreSession, { userId: "owner", sessionId: "s1" })).toBe(false);
    expect(await t.mutation(internal.commands.sessions.restoreSession, { userId: "owner", sessionId: "nope" })).toBe(false);
  });

  it("brings a marked note back with its files", async () => {
    await upload("f1");
    await saveE(entry("e1", { fileIds: ["f1"] }));
    await removeE("e1");
    expect(await t.mutation(internal.commands.entries.restoreEntry, { userId: "owner", entryId: "e1" })).toBe(true);
    const [back] = await q(api.queries.entries.recent);
    expect(back).toMatchObject({ entryId: "e1" });
    expect(back.files).toHaveLength(1);
    expect(await t.mutation(internal.commands.entries.restoreEntry, { userId: "owner", entryId: "e1" })).toBe(false);
  });

  it("cannot bring back what the purge erased", async () => {
    await saveS(pushSession("s1", NOW - 2 * HOUR));
    await removeS("s1");
    vi.setSystemTime(NOW + DELETE_AFTER_MS + HOUR);
    await purge();
    expect(await t.mutation(internal.commands.sessions.restoreSession, { userId: "owner", sessionId: "s1" })).toBe(false);
    await settle(t);
  });
});
