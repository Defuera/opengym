import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../functions/_generated/api";
import { DELETE_AFTER_MS } from "../functions/lib/constants";
import { NOW, PER_USER_TABLES, TOKEN, TOKEN_B, USER_A, USER_B, seedUser, setupTwo } from "./multiUser";
import { settle, type T } from "./helpers";

/**
 * ADR-039: two users, the same ids, nothing crosses. User A is marked "zeta", user B "omega": a word of the other user must never show up in what a user reads,
 * in the prompt of a job started for a user, or in what a user changes.
 */
let t: T;
beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
  t = setupTwo();
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

const all = (table: (typeof PER_USER_TABLES)[number]) => t.run((c) => c.db.query(table).collect());
const rowsOf = async (table: (typeof PER_USER_TABLES)[number], user: string) => (await all(table)).filter((r) => r.userId === user);
const q = (fn: unknown, token: string, args: Record<string, unknown> = {}) => t.query(fn as never, { token, ...args } as never) as Promise<unknown>;
const m = (fn: unknown, token: string, args: Record<string, unknown> = {}) => t.mutation(fn as never, { token, ...args } as never) as Promise<unknown>;
const hasBlob = (id: never) => t.run(async (c) => (await c.storage.get(id)) !== null);
const json = (x: unknown) => JSON.stringify(x ?? null);
async function seedBoth(): Promise<void> {
  await seedUser(t, TOKEN, "zeta");
  await seedUser(t, TOKEN_B, "omega");
}
/** Every row of every per-user table of one user, without the system ids that differ per row, as text. */
async function snapshot(user: string): Promise<Record<string, unknown[]>> {
  const out: Record<string, unknown[]> = {};
  for (const table of PER_USER_TABLES) out[table] = (await rowsOf(table, user)).map((r) => r);
  return out;
}

/** Every public query, with the arguments that name rows of the seed. */
const READS: [string, unknown, Record<string, unknown>][] = [
  ["sessions.recent", api.queries.sessions.recent, {}],
  ["sessions.since", api.queries.sessions.since, { since: 0 }],
  ["sessions.load", api.queries.sessions.load, { sessionId: "s1" }],
  ["sessions.planLoad", api.queries.sessions.planLoad, { exercises: [{ name: "Squat", sets: 3, minutes: 0 }] }],
  ["plans.next", api.queries.plans.next, {}],
  ["goals.list", api.queries.goals.list, {}],
  ["context.list", api.queries.context.list, {}],
  ["entries.recent", api.queries.entries.recent, {}],
  ["places.list", api.queries.places.list, {}],
  ["threads.list", api.queries.threads.list, {}],
  ["messages.list", api.queries.messages.list, { threadId: "th1" }],
  ["proposals.get", api.queries.proposals.get, { proposalId: "p1" }],
  ["proposals.open", api.queries.proposals.open, {}],
  ["proposals.forThread", api.queries.proposals.forThread, { threadId: "th1" }],
  ["programs.list", api.queries.programs.list, {}],
  ["imports.list", api.queries.imports.list, {}],
  ["imports.get", api.queries.imports.get, { importId: "i1" }],
  ["files.get", api.queries.files.get, { fileId: "f1" }],
  ["openSession.get", api.queries.openSession.get, {}],
  ["dashboard.get", api.queries.dashboard.get, { days: 7 }],
  ["reviews.get", api.queries.reviews.get, { sessionId: "s1" }],
  ["settings.ai", api.queries.settings.ai, {}],
  ["start.request", api.queries.start.request, { requestId: "sr1" }],
  ["aboutMe.get", api.queries.aboutMe.get, {}],
  ["aboutMe.askAfter", api.queries.aboutMe.askAfter, { sessionId: "s1" }],
  ["usage.summary", api.queries.usage.summary, {}],
];

describe("what a user reads", () => {
  it("every table holds the rows of both users, each with the same ids, and nothing else", async () => {
    await seedBoth();
    for (const table of PER_USER_TABLES) {
      const rows = await all(table);
      const users = new Set(rows.map((r) => r.userId));
      expect([...users].sort(), table).toEqual([USER_B, USER_A].sort());
      expect((await rowsOf(table, USER_A)).length, `${table} of A`).toBeGreaterThan(0);
      expect((await rowsOf(table, USER_B)).length, `${table} of B`).toBeGreaterThan(0);
    }
    // The same client ids, two rows: looked up by (user, id).
    expect((await all("sessions")).filter((s) => "sessionId" in s && s.sessionId === "s1")).toHaveLength(2);
    expect((await all("threads")).filter((s) => "threadId" in s && s.threadId === "th1")).toHaveLength(2);
    expect((await all("files")).filter((s) => "fileId" in s && s.fileId === "f1")).toHaveLength(2);
  });

  it("every public query returns only the rows of the caller, and no user id", async () => {
    await seedBoth();
    for (const [name, fn, args] of READS) {
      const a = json(await q(fn, TOKEN, args));
      const b = json(await q(fn, TOKEN_B, args));
      expect(a, `${name} as A`).not.toContain("omega");
      expect(b, `${name} as B`).not.toContain("zeta");
      if (name === "usage.summary") continue; // its `byUser` rows name the caller by contract (ADR-038)
      expect(a, `${name} has no user id`).not.toMatch(/"userId"/);
      expect(b, `${name} has no user id`).not.toMatch(/"userId"/);
    }
    // And they do read something of their own (a test that reads nothing proves nothing).
    expect(json(await q(api.queries.goals.list, TOKEN))).toContain("zeta");
    expect(json(await q(api.queries.goals.list, TOKEN_B))).toContain("omega");
    expect(json(await q(api.queries.messages.list, TOKEN_B, { threadId: "th1" }))).toContain("omega");
    expect(json(await q(api.queries.aboutMe.get, TOKEN))).toContain("zeta");
    expect(json(await q(api.queries.places.list, TOKEN_B))).toContain("omega");
    expect(json(await q(api.queries.entries.recent, TOKEN))).toContain("Lunch zeta");
  });

  it("one-row tables are one row per user: the open session, the model setting, the rebuild state", async () => {
    await seedBoth();
    expect(await rowsOf("openSession", USER_A)).toHaveLength(1);
    expect(await rowsOf("openSession", USER_B)).toHaveLength(1);
    expect(await rowsOf("settings", USER_A)).toHaveLength(1);
    expect(await rowsOf("rebuilds", USER_B)).toHaveLength(1);
    expect(((await q(api.queries.settings.ai, TOKEN)) as { override: string }).override).toBe("model-zeta");
    expect(((await q(api.queries.settings.ai, TOKEN_B)) as { override: string }).override).toBe("model-omega");
    expect(json(await q(api.queries.openSession.get, TOKEN))).toContain("Squat zeta");
    expect(json(await q(api.queries.openSession.get, TOKEN_B))).toContain("Squat omega");
    // A put of B replaces the row of B only; clear of B's id changes nothing for A.
    await m(api.commands.openSession.put, TOKEN_B, { session: { id: "os2", kind: "gym", type: "Gym", startedAt: NOW, exercises: [] } });
    expect(((await q(api.queries.openSession.get, TOKEN)) as { session: { id: string } }).session.id).toBe("os1");
    await m(api.commands.openSession.clear, TOKEN_B, { id: "os1" });
    expect(((await q(api.queries.openSession.get, TOKEN)) as { session: { id: string } }).session.id).toBe("os1");
  });

  it("a user with no data reads nothing of another user", async () => {
    await seedUser(t, TOKEN, "zeta");
    for (const [name, fn, args] of READS) {
      const b = json(await q(fn, TOKEN_B, args));
      expect(b, name).not.toContain("zeta");
    }
    expect(await q(api.queries.goals.list, TOKEN_B)).toEqual([]);
    expect(await q(api.queries.messages.list, TOKEN_B, { threadId: "th1" })).toEqual([]);
    expect(await q(api.queries.files.get, TOKEN_B, { fileId: "f1" })).toBeNull();
    expect(await q(api.queries.proposals.get, TOKEN_B, { proposalId: "p1" })).toBeNull();
    expect(await q(api.queries.imports.get, TOKEN_B, { importId: "i1" })).toBeNull();
    expect(await q(api.queries.start.request, TOKEN_B, { requestId: "sr1" })).toBeNull();
    expect(await q(api.queries.sessions.load, TOKEN_B, { sessionId: "s1" })).toBeNull();
    expect(await q(api.queries.reviews.get, TOKEN_B, { sessionId: "s1" })).toEqual({ review: null, stored: false });
    expect(await q(api.queries.aboutMe.askAfter, TOKEN_B, { sessionId: "s1" })).toEqual([]);
  });
});

describe("what a user changes: an id of another user is not found, and nothing changes", () => {
  /** A has data; B has none. Every call names an id of A. The answer is "not found" in the way of that function, and A's rows stay as they were. */
  it("every mutation with an id of another user answers not found", async () => {
    await seedUser(t, TOKEN, "zeta");
    const before = await snapshot(USER_A);
    const blobsBefore = (await all("files")).length;
    const notFound = /not found|no registered file|no uploaded/;
    const rejects: [string, unknown, Record<string, unknown>][] = [
      ["messages.send", api.commands.messages.send, { threadId: "th1", messageId: "mx", text: "hi" }],
      ["messages.sendVoice", api.commands.messages.sendVoice, { threadId: "th1", messageId: "mx", fileId: "f1" }],
      ["goals.update", api.commands.goals.update, { goalId: "g1", title: "stolen" }],
      ["context.update", api.commands.context.update, { itemId: "c1", text: "stolen" }],
      ["limits.addRecord", api.commands.limits.addRecord, { record: { recordId: "rx", limitId: "l1", title: "t", text: "stolen" } }],
      ["limits.checkin", api.commands.limits.checkin, { checkin: { checkinId: "cx", limitId: "l1", at: NOW, feeling: "bad" } }],
      ["programs.setStatus", api.commands.programs.setStatus, { programId: "p1", status: "paused" }],
      ["proposals.accept", api.commands.proposals.accept, { proposalId: "p2" }],
      ["proposals.request (change of a program)", api.commands.proposals.request, { proposalId: "px", kind: "program", targetId: "p1", text: "change" }],
      ["start.request (previous request)", api.commands.start.request, { requestId: "srx", feedback: "more", previousRequestId: "sr1" }],
      ["threads.create (about a program)", api.commands.threads.create, { threadId: "thx", about: { kind: "program", id: "p1" } }],
      ["entries.save (a file of A)", api.commands.entries.save, { entry: { entryId: "ex", text: "x", fileIds: ["f1"], at: NOW, createdAt: NOW } }],
    ];
    for (const [name, fn, args] of rejects) await expect(m(fn, TOKEN_B, args), name).rejects.toThrow(notFound);
    const falses: [string, unknown, Record<string, unknown>][] = [
      ["messages.retryVoice", api.commands.messages.retryVoice, { messageId: "m1" }],
      ["threads.rename", api.commands.threads.rename, { threadId: "th1", title: "stolen" }],
      ["threads.remove", api.commands.threads.remove, { threadId: "th1" }],
      ["goals.remove", api.commands.goals.remove, { goalId: "g1" }],
      ["context.remove", api.commands.context.remove, { itemId: "c1" }],
      ["limits.remove", api.commands.limits.remove, { limitId: "l1" }],
      ["limits.removeRecord", api.commands.limits.removeRecord, { recordId: "r1" }],
      ["sessions.remove", api.commands.sessions.remove, { sessionId: "s1" }],
      ["sessions.setPlace", api.commands.sessions.setPlace, { sessionId: "s1", placeId: null }],
      ["entries.remove", api.commands.entries.remove, { entryId: "e1" }],
      ["files.remove", api.commands.files.remove, { fileId: "f1" }],
      ["imports.remove", api.commands.imports.remove, { importId: "i1" }],
    ];
    for (const [name, fn, args] of falses) expect(await m(fn, TOKEN_B, args), name).toBe(false);
    // These are silent no-ops by design (nothing to report): they must not touch the row of A.
    await m(api.commands.programs.remove, TOKEN_B, { programId: "p1" });
    await m(api.commands.proposals.decline, TOKEN_B, { proposalId: "p2" });
    await m(api.commands.openSession.clear, TOKEN_B, { id: "os1" });
    expect(await snapshot(USER_A)).toEqual(before);
    expect((await all("files")).length).toBe(blobsBefore);
    // A recording of A cannot be turned into text by B, and is not dropped.
    const out = (await t.action(api.commands.voice.transcribe, { token: TOKEN_B, fileId: "f1" })) as { ok: boolean };
    expect(out.ok).toBe(false);
    expect(await snapshot(USER_A)).toEqual(before);
  });

  it("a write with the same id by another user makes a row of its own and leaves the other row alone", async () => {
    await seedBoth();
    const before = await snapshot(USER_A);
    await m(api.commands.sessions.save, TOKEN_B, { session: { sessionId: "s1", kind: "activity", type: "Walk", startedAt: NOW - 1000, endedAt: NOW, exercises: [], source: "app", note: "omega only" } });
    await m(api.commands.goals.create, TOKEN_B, { goalId: "g1", title: "omega again", kind: "custom" });
    await m(api.commands.places.save, TOKEN_B, { placeId: "pl1", name: "Gym omega", text: "changed by B" });
    await m(api.commands.limits.save, TOKEN_B, { limit: { limitId: "l1", part: "left_knee", title: "B knee", status: "cleared", rules: [] } });
    await m(api.commands.entries.save, TOKEN_B, { entry: { entryId: "e1", text: "Lunch omega, changed", fileIds: ["f1"], at: NOW - 3_600_000, createdAt: NOW - 3_600_000 } });
    await m(api.commands.threads.rename, TOKEN_B, { threadId: "th1", title: "omega thread" });
    expect(await snapshot(USER_A)).toEqual(before);
    expect(json(await q(api.queries.sessions.recent, TOKEN))).not.toContain("omega only");
    expect(json(await q(api.queries.sessions.recent, TOKEN_B))).toContain("omega only");
  });

  it("a file of one user is not found for another, also through a note and a message", async () => {
    await seedBoth();
    // Each user has an "f1" of their own: B's note holds B's file, never the one of A.
    const fa = (await rowsOf("files", USER_A))[0]!;
    const fb = (await rowsOf("files", USER_B))[0]!;
    expect(fa.storageId).not.toEqual(fb.storageId);
    expect(((await q(api.queries.files.get, TOKEN, { fileId: "f1" })) as { name: string }).name).toContain("zeta");
    expect(((await q(api.queries.files.get, TOKEN_B, { fileId: "f1" })) as { name: string }).name).toContain("omega");
    // B removes ITS f1: the blob and the row of A stay.
    expect(await m(api.commands.files.remove, TOKEN_B, { fileId: "f1" })).toBe(true);
    expect(await hasBlob(fa.storageId)).toBe(true);
    expect(await hasBlob(fb.storageId)).toBe(false);
    expect(await q(api.queries.files.get, TOKEN, { fileId: "f1" })).not.toBeNull();
  });

  it("the purge of a marked note of one user keeps the file with the same id of the other", async () => {
    await seedBoth();
    const fb = (await rowsOf("files", USER_B))[0]!;
    expect(await m(api.commands.entries.remove, TOKEN, { entryId: "e1" })).toBe(true);
    vi.setSystemTime(Date.now() + DELETE_AFTER_MS + 1000);
    await t.mutation(internal.jobs.purge.run, {});
    expect(await rowsOf("entries", USER_A)).toHaveLength(0);
    expect(await rowsOf("files", USER_A)).toHaveLength(0);
    expect(await rowsOf("entries", USER_B)).toHaveLength(1);
    expect(await rowsOf("files", USER_B)).toHaveLength(1);
    expect(await hasBlob(fb.storageId)).toBe(true);
    // The session the note made and the sessions of B stay as they were.
    expect((await rowsOf("sessions", USER_B)).length).toBeGreaterThan(0);
  });
});

describe("jobs started for a user read only that user", () => {
  it("no prompt stored for A holds a word of B, and no prompt of B holds a word of A", async () => {
    await seedBoth();
    const calls = await all("aiCalls");
    const mine = (u: string) => calls.filter((c) => c.userId === u);
    expect(mine(USER_A).length).toBeGreaterThan(5);
    expect(mine(USER_B).length).toBeGreaterThan(5);
    for (const c of mine(USER_A)) expect(json([c.system, c.messages, c.attempts]), `job ${c.job} of A`).not.toContain("omega");
    for (const c of mine(USER_B)) expect(json([c.system, c.messages, c.attempts]), `job ${c.job} of B`).not.toContain("zeta");
    // The coach saw the person's own words (the check above is not empty).
    expect(mine(USER_A).some((c) => json(c.messages).includes("zeta"))).toBe(true);
    expect(mine(USER_B).some((c) => json(c.messages).includes("omega"))).toBe(true);
  });

  it("the inputs of the jobs of A hold nothing of B (the coach picture and every job input)", async () => {
    await seedBoth();
    const run = (fn: unknown, userId: string, args: Record<string, unknown>) => t.query(fn as never, { userId, ...args } as never) as Promise<unknown>;
    const msg = (await rowsOf("messages", USER_A)).find((x) => "role" in x && x.role === "user")!;
    const inputs: [string, unknown, Record<string, unknown>][] = [
      ["coachTurn.input", internal.jobs.coachTurn.input, { threadId: "th1", messageId: (msg as { messageId: string }).messageId }],
      ["startRequest.input", internal.jobs.startRequest.input, { requestId: "sr1" }],
      ["reviews.input", internal.jobs.reviews.input, { sessionId: "s1" }],
      ["plans.input", internal.jobs.plans.input, { activity: "Gym", focus: "Push" }],
      ["dashboards.input", internal.jobs.dashboards.input, { days: 7 }],
      ["programs.input", internal.jobs.programs.input, { proposalId: "p1" }],
      ["programs.threadFiles", internal.jobs.programs.threadFiles, { proposalId: "p1" }],
      ["parseLog.input", internal.jobs.parseLog.input, { sessionId: "s2", text: "ran 5 km" }],
      ["chat.summaryInput", internal.jobs.chat.summaryInput, { threadId: "th1" }],
      ["readEntry.input", internal.jobs.readEntry.input, { entryId: "e1", rev: "x" }],
      ["places.learnInput", internal.jobs.places.learnInput, { placeId: "pl1" }],
      ["voice.input", internal.jobs.voice.input, { messageId: "m1" }],
      ["importFiles.files", internal.jobs.importFiles.files, { fileIds: ["f1"] }],
    ];
    for (const [name, fn, args] of inputs) {
      const a = json(await run(fn, USER_A, args));
      expect(a, `${name} as A`).not.toContain("omega");
      expect(json(await run(fn, USER_B, args)), `${name} as B`).not.toContain("zeta");
    }
    // The coach turn input of A is not empty and reads A's words.
    expect(json(await run(internal.jobs.coachTurn.input, USER_A, inputs[0]![2]))).toContain("zeta");
    // A job of A with an id of B finds nothing.
    const bMsg = (await rowsOf("messages", USER_B)).find((x) => "role" in x && x.role === "user")! as { messageId: string };
    expect(await run(internal.jobs.coachTurn.input, USER_A, { threadId: "th1", messageId: bMsg.messageId })).not.toContain("omega");
  });

  it("the rebuild of A changes the plans and dashboards of A only", async () => {
    await seedBoth();
    const b = await snapshot(USER_B);
    await m(api.commands.sessions.save, TOKEN, { session: { sessionId: "s9", kind: "activity", type: "Run", startedAt: NOW - 100, endedAt: NOW, exercises: [], source: "app" } });
    await settle(t);
    const b2 = await snapshot(USER_B);
    for (const table of ["plans", "dashboards", "rebuilds", "sessions", "reviews"] as const) expect(b2[table], table).toEqual(b[table]);
    expect((await rowsOf("rebuilds", USER_A))[0]).toMatchObject({ userId: USER_A });
    expect((await rowsOf("rebuilds", USER_A)).length).toBe(1);
  });
});

describe("usage splits by user", () => {
  it("the summary of a user counts the rows of that user", async () => {
    await seedBoth();
    const ua = await rowsOf("aiUsage", USER_A);
    const ub = await rowsOf("aiUsage", USER_B);
    expect(ua.length).toBeGreaterThan(5);
    expect(ub.length).toBeGreaterThan(5);
    const sa = (await q(api.queries.usage.summary, TOKEN)) as { totals: { calls: number }; byUser: { userId: string }[] };
    const sb = (await q(api.queries.usage.summary, TOKEN_B)) as { totals: { calls: number }; byUser: { userId: string }[] };
    expect(sa.totals.calls).toBe(ua.length);
    expect(sb.totals.calls).toBe(ub.length);
    expect(sa.byUser.map((u) => u.userId)).toEqual([USER_A]);
    expect(sb.byUser.map((u) => u.userId)).toEqual([USER_B]);
    // The operator report covers both, split by user.
    const all2 = (await t.query(internal.queries.usage.report, {})) as { totals: { calls: number }; byUser: { userId: string; calls: number }[] };
    expect(all2.totals.calls).toBe(ua.length + ub.length);
    expect(all2.byUser.map((u) => u.userId).sort()).toEqual([USER_A, USER_B].sort());
  });

  it("the shared exercise art is counted for the user who asked for it", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await m(api.commands.exerciseArt.request, TOKEN_B, { names: ["Hip thrust"] });
    await settle(t);
    const art = await t.run((c) => c.db.query("exerciseArt").collect());
    expect(art).toHaveLength(1);
    expect(art[0]!.status).toBe("ready");
    const images = (await rowsOf("aiUsage", USER_B)).filter((r) => r.kind === "image");
    expect(images.length).toBeGreaterThan(0);
    expect(await rowsOf("aiUsage", USER_A)).toHaveLength(0);
    // Both users read the same drawing.
    for (const token of [TOKEN, TOKEN_B]) expect(((await q(api.queries.exerciseArt.get, token, { names: ["Hip thrust"] })) as { status: string }[])[0]!.status).toBe("ready");
  });
});
