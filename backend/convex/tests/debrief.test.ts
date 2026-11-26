import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../functions/_generated/api";
import { afterSession } from "../functions/lib/debriefDb";
import { coachPicture } from "../functions/model/ai/jobs/coachPicture";
import { TOKEN, pushSession, settle, stubOpenAi, type T } from "./helpers";
import { TOKEN_B, USER_A, USER_B, setupTwo } from "./multiUser";

/** ADR-041: the debrief of a session opens one chat about it; the answer goes through the normal coach turn. */
let t: T;
const NOW = Date.UTC(2026, 10, 26, 12, 0);
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

const save = (token: string, id = "s1") => t.mutation(api.commands.sessions.save, { token, session: pushSession(id, NOW - 60_000) });
const open = (token: string, sessionId = "s1") => t.mutation(api.commands.debrief.open, { token, sessionId });
const messages = (token: string, threadId: string) => t.query(api.queries.messages.list, { token, threadId });
const threads = (userId: string) => t.run((c) => c.db.query("threads").withIndex("by_user_and_threadId", (q) => q.eq("userId", userId)).collect());

describe("opening the debrief chat", () => {
  it("makes one thread whose first message is the debrief with its question and answers", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await save(TOKEN);
    await settle(t);
    const { threadId } = await open(TOKEN);
    const m = await messages(TOKEN, threadId);
    expect(m).toHaveLength(1);
    expect(m[0]).toMatchObject({ role: "assistant", text: "Mock debrief: solid session, keep it up.", question: { text: "How do you feel?", answers: [{ id: "a1", label: "Fine" }, { id: "a2" }, { id: "a3" }] } });
    expect((await threads(USER_A))[0]).toMatchObject({ debriefOf: "s1", title: "Debrief: Gym Push" });
    expect(await t.query(api.queries.reviews.get, { token: TOKEN, sessionId: "s1" })).toMatchObject({ stored: true, debrief: { threadId, answered: false } });
  });

  it("is idempotent: a second open finds the same thread and adds nothing", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await save(TOKEN);
    await settle(t);
    const a = await open(TOKEN);
    const b = await open(TOKEN);
    expect(b).toEqual(a);
    expect(await threads(USER_A)).toHaveLength(1);
    expect(await messages(TOKEN, a.threadId)).toHaveLength(1);
  });

  it("refuses a session with no review, an unknown session, and an old-style review", async () => {
    await save(TOKEN); // AI off: no review
    await expect(open(TOKEN)).rejects.toThrow(/no debrief/);
    await expect(open(TOKEN, "nope")).rejects.toThrow(/session not found/);
    await t.run((c) => c.db.insert("reviews", { userId: USER_A, sessionId: "s1", version: 1, createdAt: 1, source: "rules", summary: "Old.", changes: [] }));
    await expect(open(TOKEN)).rejects.toThrow(/no debrief/);
    expect(await t.query(api.queries.reviews.get, { token: TOKEN, sessionId: "s1" })).toMatchObject({ stored: true, review: { summary: "Old.", changes: [] }, debrief: null });
  });

  it("is scoped by user: the same session id of another user has its own thread and review", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await save(TOKEN);
    await save(TOKEN_B);
    await settle(t);
    const a = await open(TOKEN);
    await expect(t.query(api.queries.messages.list, { token: TOKEN_B, threadId: a.threadId })).resolves.toEqual([]); // B sees nothing of A's thread
    expect(await t.query(api.queries.reviews.get, { token: TOKEN_B, sessionId: "s1" })).toMatchObject({ debrief: null });
    const b = await open(TOKEN_B);
    expect(b.threadId).toBe(a.threadId); // the id is the same string; the rows are not
    expect(await threads(USER_A)).toHaveLength(1);
    expect(await threads(USER_B)).toHaveLength(1);
  });
});

describe("answering", () => {
  it("the answer is the first user message, the coach replies, and the debrief is marked answered", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await save(TOKEN);
    await settle(t);
    const { threadId } = await open(TOKEN);
    await t.mutation(api.commands.messages.send, { token: TOKEN, threadId, messageId: "ans1", text: "A bit sore", context: { screen: "chat" } });
    await settle(t);
    const m = await messages(TOKEN, threadId);
    expect(m.map((x) => x.role)).toEqual(["assistant", "user", "assistant"]);
    expect(m[1]!.text).toBe("A bit sore");
    expect(await t.query(api.queries.reviews.get, { token: TOKEN, sessionId: "s1" })).toMatchObject({ debrief: { threadId, answered: true } });
  });
});

describe("afterSession", () => {
  const sessionDocs = (userId: string) => t.run((c) => c.db.query("sessions").withIndex("by_user_and_endedAt", (q) => q.eq("userId", userId)).collect());
  /** afterSession as the jobs call it: the sessions of `sessionsOf`, read with the id of `userId`. */
  const after = async (userId: string, sessionsOf = userId) => {
    const docs = await sessionDocs(sessionsOf);
    return t.run((c) => afterSession(c, userId, docs, NOW, "UTC"));
  };

  async function answered(token: string, userId: string) {
    vi.stubEnv("AI_PROVIDER", "mock");
    await save(token);
    await settle(t);
    const { threadId } = await open(token);
    await t.mutation(api.commands.messages.send, { token, threadId, messageId: "ans1", text: "Knee a bit sore after 50 kg", context: { screen: "chat" } });
    await settle(t);
    return after(userId);
  }

  it("holds the question, the first answer and the date of an answered debrief, only for that user", async () => {
    const mine = await answered(TOKEN, USER_A);
    expect(mine).toEqual([{ date: "2026-11-26", session: "Gym Push", question: "How do you feel?", answer: "Knee a bit sore after 50 kg" }]);
    expect(await after(USER_B, USER_A)).toEqual([]); // B reads A's session ids and finds no thread of B
  });

  it("is left out when the person did not answer", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await save(TOKEN);
    await settle(t);
    await open(TOKEN);
    expect(await after(USER_A)).toEqual([]);
  });

  it("goes into the picture of build_session and into the turn of coach_turn", async () => {
    const mine = await answered(TOKEN, USER_A);
    expect(coachPicture([], [], [], [], [], NOW, undefined, "UTC", mine).afterSession).toEqual(mine);
    expect(coachPicture([], [], [], [], [], NOW).afterSession).toBeUndefined();
    const start = (await t.run(async (c) => {
      const id = "sr1";
      await c.db.insert("startRequests", { userId: USER_A, requestId: id, name: "Gym", status: "pending", createdAt: NOW });
      return id;
    }));
    const input = await t.query(internal.jobs.startRequest.input, { userId: USER_A, requestId: start });
    expect(input!.job.picture.afterSession).toEqual(mine);

    await t.mutation(api.commands.threads.create, { token: TOKEN, threadId: "chat1" });
    const calls = stubOpenAi((job) => (job === "coach_turn" ? JSON.stringify({ message: "ok", actions: [] }) : "{}"));
    await t.mutation(api.commands.messages.send, { token: TOKEN, threadId: "chat1", messageId: "q1", text: "plan my next session", context: { screen: "chat" } });
    await settle(t);
    expect(calls.find((c) => c.job === "coach_turn")!.input.afterSession).toEqual(mine);
  });
});
