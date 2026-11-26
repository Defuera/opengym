import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../functions/_generated/api";
import { TOKEN, pushSession, setsSession, setup, settle, stubOpenAi, type T } from "./helpers";

let t: T;
const NOW = Date.UTC(2026, 10, 18, 12);
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

const savePlace = (placeId: string, name: string, text?: string) => t.mutation(api.commands.places.save, { token: TOKEN, placeId, name, ...(text !== undefined ? { text } : {}) });
const list = () => t.query(api.queries.places.list, { token: TOKEN });
const changes = () => t.run((c) => c.db.query("placeChanges").collect());
const saveSession = (s: unknown) => t.mutation(api.commands.sessions.save, { token: TOKEN, session: s as never });
const setPlace = (sessionId: string, placeId: string | null) => t.mutation(api.commands.sessions.setPlace, { token: TOKEN, sessionId, placeId });
const row = (sessionId: string) => t.run((c) => c.db.query("sessions").withIndex("by_user_and_sessionId", (q) => q.eq("userId", "owner").eq("sessionId", sessionId)).unique());

describe("places:save and places:list", () => {
  it("lists places by name with placeId, name, text and updatedAt", async () => {
    await savePlace("p-home", "Home");
    await savePlace("p-gym", "Gym", "Dumbbells, a rack");
    const places = await list();
    expect(places.map((p) => p.name)).toEqual(["Gym", "Home"]);
    expect(places[0]).toEqual({ placeId: "p-gym", name: "Gym", text: "Dumbbells, a rack", updatedAt: NOW });
    expect(places[1]!.text).toBe("");
  });

  it("is an upsert by placeId; a resend changes nothing and the text stays when it is left out", async () => {
    await savePlace("p1", "Gym", "Rack");
    await savePlace("p1", "Gym", "Rack");
    await savePlace("p1", "Big gym"); // rename only: the text stays
    expect(await list()).toMatchObject([{ placeId: "p1", name: "Big gym", text: "Rack" }]);
    expect(await t.run((c) => c.db.query("places").collect())).toHaveLength(1);
  });

  it("rejects a name whose key belongs to another place, but not the same place", async () => {
    await savePlace("p1", "Home gym");
    await expect(savePlace("p2", "  home   GYM ")).rejects.toThrow(/exists already/);
    await savePlace("p1", " HOME gym "); // the same place: allowed
    expect((await list())[0]!.name).toBe("HOME gym");
    expect(await list()).toHaveLength(1);
  });

  it("checks the sizes", async () => {
    await expect(savePlace("p", "   ")).rejects.toThrow(/name/);
    await expect(savePlace("p", "x".repeat(31))).rejects.toThrow(/name/);
    await expect(savePlace("p", "A", "x".repeat(1501))).rejects.toThrow(/text/);
    await expect(savePlace("", "A")).rejects.toThrow(/placeId/);
    await expect(savePlace("x".repeat(101), "A")).rejects.toThrow(/placeId/);
    await savePlace("p", "x".repeat(30), "y".repeat(1500));
    expect(await list()).toHaveLength(1);
  });

  it("logs a placeChanges row with source user only when the text changes", async () => {
    await savePlace("p1", "Gym"); // empty text: nothing to log
    await savePlace("p1", "Gym", "Rack");
    await savePlace("p1", "Gym", "Rack");
    await savePlace("p1", "Gym 2", "Rack");
    await savePlace("p1", "Gym 2", "Rack and bands");
    expect(await changes()).toMatchObject([
      { placeId: "p1", source: "user", before: "", after: "Rack", at: NOW },
      { placeId: "p1", source: "user", before: "Rack", after: "Rack and bands" },
    ]);
  });

  it("needs the token", async () => {
    await expect(t.mutation(api.commands.places.save, { token: "bad", placeId: "p", name: "A" })).rejects.toThrow();
    await expect(t.query(api.queries.places.list, { token: "bad" })).rejects.toThrow();
  });
});

describe("the place of a session", () => {
  it("save stores the placeId as given (an unknown place too) and the reads return it", async () => {
    await saveSession({ ...setsSession("s1", NOW - 1000), placeId: "ahead-of-the-server" });
    expect(await row("s1")).toMatchObject({ placeId: "ahead-of-the-server" });
    expect((await t.query(api.queries.sessions.recent, { token: TOKEN }))[0]).toMatchObject({ placeId: "ahead-of-the-server" });
    expect((await t.query(api.queries.sessions.since, { token: TOKEN, since: 0 }))[0]).toMatchObject({ placeId: "ahead-of-the-server" });
  });

  it("a save WITHOUT placeId (an old app) keeps the stored one; a save with another one replaces it", async () => {
    await saveSession({ ...pushSession("s1", NOW - 1000), placeId: "p-gym" });
    await saveSession({ ...pushSession("s1", NOW - 1000, 70) }); // an edit from an old app
    expect(await row("s1")).toMatchObject({ placeId: "p-gym" });
    expect((await row("s1"))!.exercises[0]!.sets[1]).toMatchObject({ kg: 70 });
    await saveSession({ ...pushSession("s1", NOW - 1000, 70), placeId: "p-home" });
    expect(await row("s1")).toMatchObject({ placeId: "p-home" });
    await saveSession(pushSession("s1", NOW - 1000, 70)); // a resend with nothing new
    expect(await row("s1")).toMatchObject({ placeId: "p-home" });
  });

  it("a session saved with no place has none", async () => {
    await saveSession(pushSession("s1", NOW - 1000));
    expect((await row("s1"))!.placeId).toBeUndefined();
    expect((await t.query(api.queries.sessions.recent, { token: TOKEN }))[0]).not.toHaveProperty("placeId");
  });

  it("setPlace sets and clears the place of one session and changes nothing else", async () => {
    await saveSession(pushSession("s1", NOW - 1000));
    await saveSession(pushSession("s2", NOW - 2000));
    const before = await row("s1");
    expect(await setPlace("s1", "p-home")).toBe(true);
    const after = await row("s1");
    expect(after).toMatchObject({ placeId: "p-home" });
    const { placeId, ...rest } = after!;
    void placeId;
    const { placeId: _p, ...restBefore } = before as typeof before & { placeId?: string };
    void _p;
    expect(rest).toEqual(restBefore);
    expect((await row("s2"))!.placeId).toBeUndefined();
    expect(await setPlace("s1", null)).toBe(true);
    expect((await row("s1"))!.placeId).toBeUndefined();
    await expect(setPlace("s1", "")).rejects.toThrow(/placeId/);
  });

  it("setPlace on an unknown or deleted session returns false and brings nothing back", async () => {
    expect(await setPlace("nope", "p")).toBe(false);
    await saveSession(pushSession("s1", NOW - 1000));
    await t.mutation(api.commands.sessions.remove, { token: TOKEN, sessionId: "s1" });
    expect(await setPlace("s1", "p")).toBe(false);
    expect((await row("s1"))!.placeId).toBeUndefined();
    expect(await t.query(api.queries.sessions.recent, { token: TOKEN })).toEqual([]);
  });
});

describe("a chat thread about a place", () => {
  const create = (threadId: string, placeId?: string) => t.mutation(api.commands.threads.create, { token: TOKEN, threadId, ...(placeId ? { placeId } : {}) });
  const threads = () => t.query(api.queries.threads.list, { token: TOKEN });

  it("create stores the placeId and the list returns it; a thread without one has none", async () => {
    await create("th1", "p-home");
    await create("th2");
    await create("th1", "other"); // a resend changes nothing
    const by = Object.fromEntries((await threads()).map((x) => [x.threadId, x]));
    expect(by.th1).toMatchObject({ placeId: "p-home", title: "New chat" });
    expect(by.th2!.placeId).toBeUndefined();
    await expect(create("th3", "x".repeat(101))).rejects.toThrow(/placeId/);
  });

  it("the coach turn of the thread reads the place in view and every place with its note", async () => {
    await savePlace("p-home", "Home", "A pair of 10 kg dumbbells");
    await create("th1", "p-home");
    await t.mutation(api.commands.messages.send, { token: TOKEN, threadId: "th1", messageId: "m1", text: "I also have a pull-up bar" });
    const input = await t.query(internal.jobs.coachTurn.input, { userId: "owner", threadId: "th1", messageId: "m1" });
    expect(input!.turn).toMatchObject({ placeInView: { placeId: "p-home", name: "Home" } });
    expect(input!.turn.places).toContainEqual({ placeId: "p-home", name: "Home", equipment: "A pair of 10 kg dumbbells", knowledge: "partial" });
  });

  it("a thread without a place, or with a place that is gone, gives the coach no place", async () => {
    await create("th1");
    await create("th2", "gone");
    await t.mutation(api.commands.messages.send, { token: TOKEN, threadId: "th1", messageId: "m1", text: "hello" });
    await t.mutation(api.commands.messages.send, { token: TOKEN, threadId: "th2", messageId: "m2", text: "hello" });
    expect((await t.query(internal.jobs.coachTurn.input, { userId: "owner", threadId: "th1", messageId: "m1" }))!.turn.placeInView).toBeUndefined();
    expect((await t.query(internal.jobs.coachTurn.input, { userId: "owner", threadId: "th2", messageId: "m2" }))!.turn.placeInView).toBeUndefined();
  });

  it("a message in a place thread runs no learn_place job: the coach turn updates the place itself, with the person's words as evidence", async () => {
    await savePlace("p-home", "Home");
    await create("th1", "p-home");
    const calls = stubOpenAi((job) => (job === "coach_turn" ? JSON.stringify({ message: "Noted the bar.", actions: [{ id: "a1", name: "update_place", arguments: { placeId: "p-home", add: "Pull-up bar", evidence: "person_said" } }] }) : "{}"));
    await t.mutation(api.commands.messages.send, { token: TOKEN, threadId: "th1", messageId: "m1", text: "x".repeat(400) });
    await settle(t);
    expect(calls.filter((c) => c.job === "learn_place")).toHaveLength(0);
    expect((await list())[0]).toMatchObject({ text: "Pull-up bar" });
    const log = await changes();
    expect(log).toMatchObject([{ placeId: "p-home", source: "chat", evidence: "person_said", before: "", after: "Pull-up bar" }]);
    expect(log[0]!.quote).toBe("x".repeat(300));
  });

  it("with the mock provider a sentence that names equipment updates the place and any other sentence changes nothing", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await savePlace("p-home", "Home", "Two dumbbells");
    await create("th1", "p-home");
    await t.mutation(api.commands.messages.send, { token: TOKEN, threadId: "th1", messageId: "m1", text: "How are you today?" });
    await settle(t);
    expect((await list())[0]!.text).toBe("Two dumbbells");
    await t.mutation(api.commands.messages.send, { token: TOKEN, threadId: "th1", messageId: "m2", text: "I have a rack here" });
    await settle(t);
    expect((await list())[0]!.text).toBe("Two dumbbells\nRack");
  });
});
