import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "../functions/_generated/api";
import { LOG_NO_AI, LOG_NO_PHOTO, LOG_UNREAD } from "../functions/model/logDraft";
import { TOKEN, setup, settle, stubOpenAi, type T } from "./helpers";

/** ADR-032: the log chat. The coach drafts a log; "Done" writes it in plain code. */
const NOW = Date.UTC(2026, 10, 24, 10);
const YESTERDAY = new Date(NOW - 86_400_000).toISOString();
const LOG = { screen: "log" as const };
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

async function world() {
  await t.mutation(api.commands.threads.create, { token: TOKEN, threadId: "th1", title: "Log" });
}
async function upload(fileId: string) {
  const storageId = await t.run((c) => c.storage.store(new Blob(["x"], { type: "image/jpeg" })));
  await t.mutation(api.commands.files.register, { token: TOKEN, fileId, storageId, name: `${fileId}.jpg`, mime: "image/jpeg", size: 1 });
}
const send = (messageId: string, text: string, fileIds?: string[], answer?: { turnId: string; id: string }, context: object = LOG) =>
  t.mutation(api.commands.messages.send, { token: TOKEN, threadId: "th1", messageId, text, context, ...(fileIds ? { fileIds } : {}), ...(answer ? { answer } : {}) });
const done = (messageId: string, turnId: string) => send(messageId, "Done", undefined, { turnId, id: "approve" });
const messages = () => t.query(api.queries.messages.list, { token: TOKEN, threadId: "th1" });
const lastAssistant = async () => (await messages()).filter((m) => m.role === "assistant").at(-1)!;
const entries = () => t.run((c) => c.db.query("entries").collect());
const sessions = () => t.run((c) => c.db.query("sessions").collect());
const table = <N extends "goals" | "limits" | "context">(n: N) => t.run((c) => c.db.query(n).collect());
const reply = (turn: () => object) => (job: string) => (job === "coach_turn" ? JSON.stringify(turn()) : job === "summarise_thread" ? JSON.stringify({ summary: "s" }) : "{}");
const draft = (args: object, message = "Understood.") => ({ message, actions: [{ id: "a1", name: "draft_log", arguments: args }] });
const RUN = (km: number) => ({ kind: "training", summary: `Run, ${km} km in 30 min`, at: YESTERDAY, session: { kind: "activity", type: "Run", minutes: 30, distanceKm: km } });

describe("a draft writes nothing", () => {
  it("dinner with a photo: kind meal; Done writes one entry, labelled, with no reader job and no session", async () => {
    await world();
    await upload("f1");
    const calls = stubOpenAi(reply(() => draft({ kind: "meal", color: "#b45309", summary: "dinner, pasta with tomato sauce" })));
    await send("m1", "dinner", ["f1"]);
    await settle(t);
    const a = await lastAssistant();
    expect(a).toMatchObject({ turnId: "m1", actions: [{ name: "draft_log", status: "drafted" }], question: { answers: [{ id: "approve", label: "Done" }, { id: "change", label: "Add or change" }] }, proposal: { type: "log", kind: "Meal", color: "#B45309", state: "open" } });
    expect(await entries()).toHaveLength(0);
    expect(await sessions()).toHaveLength(0);
    await done("m2", "m1");
    await settle(t);
    const [e] = await entries();
    expect(e).toMatchObject({ text: "dinner", fileIds: ["f1"], read: { status: "ready", kind: "Meal", summary: "dinner, pasta with tomato sauce" } });
    expect(e!.read!.made).toBeUndefined();
    expect(await sessions()).toHaveLength(0);
    expect(calls.filter((c) => c.job === "read_entry")).toHaveLength(0);
    const last = await lastAssistant();
    expect(last).toMatchObject({ text: "Logged: dinner, pasta with tomato sauce.", entryId: e!.entryId });
    expect((await messages()).find((m) => m.proposal)!.proposal).toMatchObject({ state: "applied", entryId: e!.entryId });
  });

  it("a run in words: Done writes the entry and one activity session of yesterday, tagged; a second Done is a no-op", async () => {
    await world();
    stubOpenAi(reply(() => draft(RUN(5))));
    await send("m1", "ran 5 km in 30 min yesterday");
    await settle(t);
    expect((await lastAssistant()).proposal).toMatchObject({ type: "log", kind: "Training", session: { type: "Run", minutes: 30, distanceKm: 5, exercises: [] } });
    expect(await sessions()).toHaveLength(0);
    await done("m2", "m1");
    await done("m3", "m1");
    await settle(t);
    const [e] = await entries();
    const [s] = await sessions();
    expect(await entries()).toHaveLength(1);
    expect(await sessions()).toHaveLength(1);
    expect(s).toMatchObject({ kind: "activity", type: "Run", minutes: 30, distanceKm: 5, source: "import", importId: e!.entryId, endedAt: Date.parse(YESTERDAY) });
    expect(e!.read!.made).toEqual({ sessionId: s!.sessionId });
    expect(e!.at).toBe(Date.parse(YESTERDAY));
    const msgs = (await messages()).filter((m) => m.role === "assistant");
    expect(msgs[1]!.text).toBe("Logged: Run, 5 km in 30 min, yesterday. Session added.");
    expect(msgs[2]!.text).toContain("already");
    const recent = await t.query(api.queries.entries.recent, { token: TOKEN });
    expect(recent[0]!.read).toMatchObject({ made: { sessionId: s!.sessionId } });
  });

  it("a second message replaces the draft; Done writes the newer one and both messages", async () => {
    await world();
    let km = 5;
    stubOpenAi(reply(() => draft(RUN(km))));
    await send("m1", "ran 5 km in 30 min yesterday");
    await settle(t);
    km = 6;
    await send("m2", "it was 6 km");
    await settle(t);
    expect((await messages()).filter((m) => m.proposal).map((m) => m.proposal!.state)).toEqual(["stale", "open"]);
    await done("m3", "m1");
    expect((await lastAssistant()).text).toContain("newer draft");
    expect(await entries()).toHaveLength(0);
    await done("m4", "m2");
    await settle(t);
    expect((await sessions())[0]).toMatchObject({ distanceKm: 6 });
    expect((await entries())[0]!.text).toBe("ran 5 km in 30 min yesterday\n\nit was 6 km");
  });

  it("\"Add or change\" runs a normal turn, and is not part of the entry text", async () => {
    await world();
    const calls = stubOpenAi(reply(() => draft({ kind: "other", summary: "a note" })));
    await send("m1", "felt good");
    await settle(t);
    await send("m2", "Add or change", undefined, { turnId: "m1", id: "change" });
    await settle(t);
    expect(calls.filter((c) => c.job === "coach_turn")).toHaveLength(2);
    await done("m3", "m2");
    expect((await entries())[0]!.text).toBe("felt good");
  });

  it("a goal and a lasting limit are written on Done only, tagged with the entry", async () => {
    await world();
    stubOpenAi(reply(() => draft({ kind: "body", summary: "no deep squats for a month", goal: { title: "Bench press 80 kg", kind: "strength", exercise: "Bench press", targetKg: 80 }, limit: { part: "left_knee", title: "Deep squats", status: "active", rules: [{ kind: "avoid", text: "No deep squats", exercises: ["Deep squat"] }] }, note: { text: "Knee needs care", topic: "knee" } })));
    await send("m1", "I must avoid deep squats for a month, and I want to bench 80 kg");
    await settle(t);
    expect(await table("goals")).toHaveLength(0);
    expect(await table("limits")).toHaveLength(0);
    await done("m2", "m1");
    await settle(t);
    const [e] = await entries();
    const [g] = await table("goals");
    const [l] = await table("limits");
    const [c] = await table("context");
    expect(g).toMatchObject({ title: "Bench press 80 kg", importId: e!.entryId, status: "active" });
    expect(l).toMatchObject({ part: "left_knee", importId: e!.entryId });
    expect(c).toMatchObject({ text: "Knee needs care", importId: e!.entryId, active: true });
    expect(e!.read!.made).toEqual({ goalId: g!.goalId, limitId: l!.limitId, contextId: c!.itemId });
  });
});

describe("bad drafts and no AI", () => {
  it("an invalid session part: one retry, then a reply with no draft", async () => {
    await world();
    const calls = stubOpenAi(reply(() => draft({ kind: "training", summary: "swim", session: { kind: "swim", type: "Swim" } })));
    await send("m1", "swam");
    await settle(t);
    expect(calls.filter((c) => c.job === "coach_turn")).toHaveLength(2);
    const a = await lastAssistant();
    expect(a.text).toBe(LOG_UNREAD);
    expect(a.proposal).toBeUndefined();
  });

  it("a gym session told in words keeps an exercise that has no sets and no usual sets, and Done writes it with no sets", async () => {
    await world();
    stubOpenAi(reply(() => draft({ kind: "training", summary: "legs", session: { kind: "gym", type: "Gym", exercises: [{ name: "Mystery lift", sets: [] }] } })));
    await send("m1", "did mystery lift");
    await settle(t);
    const a = await lastAssistant();
    expect(a.proposal).toMatchObject({ type: "log", kind: "Training", session: { type: "Gym", exercises: [{ name: "Mystery lift", sets: "" }] } });
    expect(a.actions![0]).toMatchObject({ status: "drafted", detail: "Drafted a log (Training: session)" });
    expect(a.actions![0]!.reason).toBeUndefined(); // nothing was dropped
    await done("m2", "m1");
    await settle(t);
    const [s] = await sessions();
    expect(s).toMatchObject({ kind: "gym", type: "Gym", source: "import", exercises: [{ name: "Mystery lift", sets: [] }] });
  });

  it("an exercise with no sets takes the usual sets of the log; one with sets stays as given; a time exercise with no sets stays too", async () => {
    await world();
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: { sessionId: "old", kind: "gym", type: "Gym", startedAt: NOW - 8 * 86_400_000, endedAt: NOW - 8 * 86_400_000 + 3_600_000, exercises: [{ name: "Bench press", sets: [{ reps: 8, kg: 60, max: false }] }], source: "app" } });
    stubOpenAi(reply(() => draft({ kind: "training", summary: "push", session: { kind: "gym", type: "Gym", exercises: [{ name: "bench press", sets: [] }, { name: "Dips", sets: [{ reps: 10, kg: 0 }] }, { name: "Plank", measure: "time", sets: [] }] } })));
    await send("m1", "bench, dips and a plank");
    await settle(t);
    expect((await lastAssistant()).proposal).toMatchObject({ session: { exercises: [{ name: "Bench press", sets: expect.stringContaining("8") }, { name: "Dips" }, { name: "Plank", sets: "" }] } });
    await done("m2", "m1");
    await settle(t);
    const s = (await sessions()).find((x) => x.sessionId !== "old")!;
    expect(s.exercises.map((e) => e.name)).toEqual(["Bench press", "Dips", "Plank"]);
    expect(s.exercises[0]!.sets).toEqual([{ reps: 8, kg: 60, max: false }]);
    expect(s.exercises[2]).toMatchObject({ measure: "time", sets: [] });
  });

  it("a gym session with no exercise at all is not dropped either", async () => {
    await world();
    stubOpenAi(reply(() => draft({ kind: "training", summary: "went to the gym", session: { kind: "gym", type: "Gym", exercises: [] } })));
    await send("m1", "went to the gym");
    await settle(t);
    expect((await lastAssistant()).proposal).toMatchObject({ session: { type: "Gym", exercises: [] } });
  });

  it("with no AI: a fixed message, and Done saves a plain note of kind other", async () => {
    await world();
    await send("m1", "had pasta");
    await settle(t);
    const a = await lastAssistant();
    expect(a.text).toBe(LOG_NO_AI);
    expect(a.proposal).toMatchObject({ type: "log", kind: "other", state: "open" });
    await done("m2", "m1");
    expect((await entries())[0]).toMatchObject({ text: "had pasta", read: { status: "ready", kind: "other" } });
  });

  it("photos only and a provider with no image input: a fixed message, Done still saves a plain note", async () => {
    vi.stubEnv("AI_PROVIDER", "deepseek");
    vi.stubEnv("DEEPSEEK_API_KEY", "k");
    const fetched = vi.fn();
    vi.stubGlobal("fetch", fetched);
    await world();
    await upload("f1");
    await send("m1", "", ["f1"]);
    await settle(t);
    expect(fetched).not.toHaveBeenCalled();
    const a = await lastAssistant();
    expect(a.text).toBe(LOG_NO_PHOTO);
    expect(a.proposal).toMatchObject({ type: "log", kind: "other" });
    await done("m2", "m1");
    expect((await entries())[0]).toMatchObject({ fileIds: ["f1"], read: { kind: "other" } });
  });

  it("the mock provider drafts a run", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await world();
    await send("m1", "ran 5 km in 30 min yesterday");
    await settle(t);
    expect((await lastAssistant()).proposal).toMatchObject({ type: "log", session: { type: "Run", distanceKm: 5 } });
  });
});

describe("the rest of the chat", () => {
  it("a message from the log screen can still update a place", async () => {
    await t.mutation(api.commands.places.save, { token: TOKEN, placeId: "p-gym", name: "Gym", text: "Rack" });
    await world();
    stubOpenAi(reply(() => ({ message: "Noted the board at the Gym.", actions: [{ id: "a1", name: "update_place", arguments: { placeId: "p-gym", add: "Balance board", evidence: "person_said" } }] })));
    await send("m1", "the gym has a balance board", undefined, undefined, { screen: "log", placeId: "p-gym" });
    await settle(t);
    expect((await t.query(api.queries.places.list, { token: TOKEN })).find((p) => p.placeId === "p-gym")!.text).toContain("Balance board");
    expect((await lastAssistant()).proposal).toBeUndefined();
  });

  it("removing the entry marks the session it made as deleted; goal, limit and note stay", async () => {
    await world();
    stubOpenAi(reply(() => draft({ ...RUN(5), goal: { title: "Run more", kind: "custom" } })));
    await send("m1", "ran 5 km in 30 min yesterday");
    await settle(t);
    await done("m2", "m1");
    const [e] = await entries();
    expect(await t.mutation(api.commands.entries.remove, { token: TOKEN, entryId: e!.entryId })).toBe(true);
    expect((await sessions())[0]!.deletedAt).toBeDefined();
    expect(await table("goals")).toHaveLength(1);
    expect(await t.query(api.queries.sessions.recent, { token: TOKEN })).toHaveLength(0);
  });

  it("the coach reads the record in its context (not in INPUT_JSON), and an entry that made a session is not read as a second note", async () => {
    await world();
    await t.mutation(api.commands.limits.save, { token: TOKEN, limit: { limitId: "k1", part: "left_knee", title: "Knee", status: "active", rules: [{ kind: "avoid", text: "Deep squats" }] } });
    await t.mutation(api.commands.limits.addRecord, { token: TOKEN, record: { recordId: "r1", limitId: "k1", title: "Scan", text: "PRIVATE-RECORD-TEXT" } });
    const bodies: string[] = [];
    const calls = stubOpenAi(reply(() => draft(RUN(5))));
    const inner = globalThis.fetch;
    vi.stubGlobal("fetch", async (u: string, init: RequestInit) => {
      bodies.push(String(init.body));
      return inner(u, init);
    });
    await send("m1", "ran 5 km in 30 min yesterday");
    await settle(t);
    await done("m2", "m1");
    await send("m3", "how was my week?");
    await settle(t);
    expect(bodies.length).toBeGreaterThan(1);
    expect(bodies.join("")).toContain("PRIVATE-RECORD-TEXT"); // ADR-033: the coach reads the person's records
    const turn = calls.filter((c) => c.job === "coach_turn").at(-1)!;
    expect(turn.input).toMatchObject({ screen: "log", today: "2026-11-24 (Tuesday)" });
    expect(JSON.stringify(turn.input)).not.toContain("PRIVATE-RECORD-TEXT"); // the lists the coach may change carry no record
    expect(turn.input).not.toHaveProperty("currentLogDraft"); // the draft was applied
    const last = JSON.parse(bodies.filter((b) => b.includes("INPUT_JSON")).at(-1)!);
    expect(JSON.stringify(last)).not.toContain("Log entries from the user");
  });
});
