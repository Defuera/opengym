import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../functions/_generated/api";
import { COACH_TURN_FALLBACK, coachTurnJob } from "../functions/model/ai/jobs/coachTurn";
import { learnPlaceJob } from "../functions/model/ai/jobs/learnPlace";
import type { OpenExercise } from "../functions/model/openSession";
import { TOKEN, setup, settle, stubOpenAi, type T } from "./helpers";

/** ADR-032 step A: one chat turn with functions, sent from the session or an exercise. */
let t: T;
beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(Date.UTC(2026, 10, 24, 10));
  t = setup();
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

const set = (done: boolean) => ({ reps: 10, kg: 40, max: false, done });
const EXERCISES: OpenExercise[] = [
  { id: "e1", name: "Squat", sets: [set(true), set(false)], fresh: false, carry: false },
  { id: "e2", name: "Single-leg stand", measure: "time", sets: [{ minutes: 1, done: false }], fresh: false, carry: false, note: "No balance board at the gym" },
  { id: "e3", name: "Leg press", sets: [set(false), set(false)], fresh: false, carry: false },
];
const BALANCE = { name: "Balance board stand", measure: "time", sets: [{ minutes: 1 }], note: "On the balance board" };
const CONTEXT = { screen: "exercise" as const, openSessionId: "s1", exerciseId: "e2" };

async function world() {
  await t.mutation(api.commands.places.save, { token: TOKEN, placeId: "p-gym", name: "Gym", text: "Rack, barbell, leg press" });
  await t.mutation(api.commands.places.save, { token: TOKEN, placeId: "p-home", name: "Home", text: "Balance board, dumbbells" });
  await t.mutation(api.commands.openSession.put, { token: TOKEN, session: { id: "s1", kind: "gym", type: "Gym", focus: "Legs", startedAt: 1000, placeId: "p-gym", exercises: EXERCISES } });
  await t.mutation(api.commands.threads.create, { token: TOKEN, threadId: "th1", title: "Coach" });
}
const send = (messageId: string, text: string, context?: object) => t.mutation(api.commands.messages.send, { token: TOKEN, threadId: "th1", messageId, text, ...(context ? { context } : {}) });
const open = () => t.query(api.queries.openSession.get, { token: TOKEN });
const messages = () => t.query(api.queries.messages.list, { token: TOKEN, threadId: "th1" });
const gym = async () => (await t.query(api.queries.places.list, { token: TOKEN })).find((p) => p.placeId === "p-gym")!;
const changes = () => t.run((c) => c.db.query("placeChanges").collect());
const turns = (calls: { job: string }[]) => calls.filter((c) => c.job === "coach_turn");
/** The coach answers coach_turn with `turn` and any other job with a valid small answer. */
const coach = (turn: (input: any) => object | string) => (job: string, input: any) => (job === "coach_turn" ? (typeof turn(input) === "string" ? (turn(input) as string) : JSON.stringify(turn(input))) : job === "summarise_thread" ? JSON.stringify({ summary: "s" }) : "{}"); // eslint-disable-line @typescript-eslint/no-explicit-any

const balanceTurn = (input: any) => // eslint-disable-line @typescript-eslint/no-explicit-any
  input.currentExercise
    ? {
        message: "Swapped the stand for the balance board, and noted the board at the Gym.",
        actions: [
          { id: "a1", name: "update_place", arguments: { placeId: input.sessionPlace.placeId, add: "Balance board", evidence: "person_said" } },
          { id: "a2", name: "replace_open_exercise", arguments: { exerciseId: input.currentExercise.id, exercise: BALANCE } },
        ],
      }
    : { message: "?", actions: [] };

describe("the balance-board case (owner, 2026-11-24)", () => {
  it("replaces one exercise, keeps the place, updates the Gym text and logs the evidence, in one turn", async () => {
    await world();
    const before = (await open()).session!;
    const calls = stubOpenAi(coach(balanceTurn));
    await send("m1", "I do have a balance board", CONTEXT);
    await settle(t);

    // The model saw the server's session with ids and the place facts.
    const input = turns(calls)[0]!.input;
    expect(input).toMatchObject({ screen: "exercise", currentExercise: { id: "e2" }, sessionPlace: { placeId: "p-gym", name: "Gym" }, openSession: { id: "s1", place: "Gym" } });
    expect(input.openSession.exercises.map((e: { personsWork: boolean }) => e.personsWork)).toEqual([true, false, false]);
    expect(input.places).toContainEqual({ placeId: "p-gym", name: "Gym", equipment: "Rack, barbell, leg press", knowledge: "partial", isSessionPlace: true });

    const r = await open();
    expect(r).toMatchObject({ rev: 2, updatedBy: "coach" });
    const s = r.session!;
    expect(s.placeId).toBe("p-gym");
    expect(s.exercises).toHaveLength(3);
    expect(s.exercises[0]).toEqual(before.exercises[0]);
    expect(s.exercises[2]).toEqual(before.exercises[2]);
    expect(s.exercises[1]).toMatchObject({ name: "Balance board stand", measure: "time", sets: [{ minutes: 1, done: false }], note: "On the balance board" });
    expect(s.exercises[1]!.id).not.toBe("e2");

    expect((await gym()).text).toBe("Rack, barbell, leg press\nBalance board");
    expect(await changes()).toMatchObject([
      { placeId: "p-gym", source: "user" },
      { placeId: "p-home", source: "user" },
      { placeId: "p-gym", source: "chat", evidence: "person_said", quote: "I do have a balance board", before: "Rack, barbell, leg press", after: "Rack, barbell, leg press\nBalance board" },
    ]);
    const ms = await messages();
    expect(ms[0]).toMatchObject({ role: "user", context: CONTEXT });
    expect(ms[1]).toMatchObject({
      role: "assistant",
      turnId: "m1",
      text: "Swapped the stand for the balance board, and noted the board at the Gym.",
      actions: [
        { actionId: "a1", name: "update_place", status: "applied", detail: "Gym: added Balance board" },
        { actionId: "a2", name: "replace_open_exercise", status: "applied", detail: "Single-leg stand → Balance board stand" },
      ],
    });
    expect(await t.run((c) => c.db.query("aiCalls").withIndex("by_job", (q) => q.eq("job", "coach_turn")).collect())).toHaveLength(1);
  });

  it("a repeated turn changes nothing more", async () => {
    await world();
    const calls = stubOpenAi(coach(balanceTurn));
    await send("m1", "I do have a balance board", CONTEXT);
    await settle(t);
    const after = await open();
    await t.action(internal.jobs.coachTurn.run, { threadId: "th1", messageId: "m1" });
    await settle(t);
    expect(turns(calls)).toHaveLength(2);
    expect(await open()).toEqual(after);
    expect((await gym()).text).toBe("Rack, barbell, leg press\nBalance board");
    expect((await changes()).filter((c) => c.source === "chat")).toHaveLength(1);
    expect((await messages()).filter((m) => m.role === "assistant")).toHaveLength(1);
    const th = (await t.query(api.queries.threads.list, { token: TOKEN }))[0]!;
    expect(th).toMatchObject({ status: "idle", pending: 0 });
  });

  it("the mock provider plays the same case", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await world();
    await send("m1", "I do have a balance board", CONTEXT);
    await settle(t);
    const s = (await open()).session!;
    expect(s.exercises.map((e) => e.name)).toEqual(["Squat", "Balance board stand", "Leg press"]);
    expect(s.placeId).toBe("p-gym");
    expect((await gym()).text).toContain("Balance board");
  });
});

describe("the coach turn refuses what it may not do", () => {
  it("an exercise with a done set is not replaced", async () => {
    await world();
    stubOpenAi(coach(() => ({ message: "Changed squat.", actions: [{ id: "a1", name: "replace_open_exercise", arguments: { exerciseId: "e1", exercise: BALANCE } }] })));
    await send("m1", "change the squat", { ...CONTEXT, exerciseId: "e1" });
    await settle(t);
    expect(await open()).toMatchObject({ rev: 1, updatedBy: "app" });
    const a = (await messages())[1]!;
    expect(a.actions).toEqual([{ actionId: "a1", name: "replace_open_exercise", status: "rejected", reason: "the person has done a set of it or commented on it" }]);
  });

  it("the trace of the turn in aiCalls holds the result of each action, the rejected ones with the reason", async () => {
    await world();
    stubOpenAi(coach(() => ({ message: "Done.", actions: [{ id: "a1", name: "replace_open_exercise", arguments: { exerciseId: "e1", exercise: BALANCE } }, { id: "a2", name: "remove_open_exercise", arguments: { exerciseId: "e3" } }] })));
    await send("m1", "change the squat and drop the leg press", { ...CONTEXT, exerciseId: "e1" });
    await settle(t);
    const [call] = await t.run((c) => c.db.query("aiCalls").withIndex("by_job", (q) => q.eq("job", "coach_turn")).collect());
    expect(call).toMatchObject({
      ref: "m1",
      path: "ai",
      actions: [
        { actionId: "a1", name: "replace_open_exercise", status: "rejected", reason: "the person has done a set of it or commented on it" },
        { actionId: "a2", name: "remove_open_exercise", status: "applied" },
      ],
    });
    // The same results are on the message the person reads.
    expect((await messages())[1]!.actions).toMatchObject([{ status: "rejected" }, { status: "applied" }]);
  });

  for (const [label, action] of [
    ["an unknown tool name", { id: "a1", name: "set_open_session_place", arguments: { placeId: "p-home" } }],
    ["bad arguments", { id: "a1", name: "replace_open_exercise", arguments: { exerciseId: "e2" } }],
  ] as const) {
    it(`${label}: one retry, then the fallback with no writes`, async () => {
      await world();
      const calls = stubOpenAi(coach(() => ({ message: "Moved you home.", actions: [action] })));
      await send("m1", "I do have a balance board", CONTEXT);
      await settle(t);
      expect(turns(calls)).toHaveLength(2);
      expect(await open()).toMatchObject({ rev: 1, updatedBy: "app", session: { placeId: "p-gym" } });
      expect((await gym()).text).toBe("Rack, barbell, leg press");
      expect((await changes()).filter((c) => c.source === "chat")).toHaveLength(0);
      expect((await messages())[1]).toMatchObject({ role: "assistant", text: COACH_TURN_FALLBACK, actions: [], turnId: "m1" });
    });
  }

  it("a stale rev or another session id is rejected", async () => {
    await world();
    await send("m1", "swap it", CONTEXT);
    await t.mutation(api.commands.openSession.put, { token: TOKEN, session: { id: "s1", kind: "gym", type: "Gym", startedAt: 1000, placeId: "p-gym", exercises: EXERCISES } }); // rev 2: the phone changed it
    const replace = { id: "a1", name: "replace_open_exercise", arguments: { exerciseId: "e2", exercise: BALANCE } };
    const stale = await t.mutation(internal.jobs.coachTurn.save, { threadId: "th1", turnId: "m1", openSessionId: "s1", rev: 1, message: "x", actions: [replace], sources: [] });
    expect(stale).toEqual([{ actionId: "a1", name: "replace_open_exercise", status: "rejected", reason: "the session changed since the coach read it" }]);
    const other = await t.mutation(internal.jobs.coachTurn.save, { threadId: "th1", turnId: "m2", openSessionId: "s0", rev: 2, message: "x", actions: [replace], sources: [] });
    expect(other[0]).toMatchObject({ status: "rejected", reason: "another session is open now" });
    expect((await open()).rev).toBe(2);
  });

  it("a place change needs the person's own words or photo; an avoided exercise is refused; ids are used once", async () => {
    await world();
    await t.run((c) => c.db.insert("limits", { limitId: "l1", part: "left_knee", title: "Knee", status: "active", rules: [{ kind: "avoid", text: "no stands", exercises: ["Balance board stand"] }] }));
    await send("m1", "hi", CONTEXT);
    const r = await t.mutation(internal.jobs.coachTurn.save, {
      threadId: "th1",
      turnId: "m1",
      openSessionId: "s1",
      rev: 1,
      message: "x",
      actions: [
        { id: "a1", name: "update_place", arguments: { placeId: "p-gym", add: "Bike", evidence: "seen_in_photo" } },
        { id: "a2", name: "replace_open_exercise", arguments: { exerciseId: "e2", exercise: BALANCE } },
        { id: "a3", name: "remove_open_exercise", arguments: { exerciseId: "e3" } },
        { id: "a3", name: "remove_open_exercise", arguments: { exerciseId: "e2" } },
      ],
      sources: [],
    });
    expect(r.map((x) => [x.actionId, x.status, x.reason])).toEqual([
      ["a1", "rejected", "no photo in this turn"],
      ["a2", "rejected", "a limit marks this exercise avoid"],
      ["a3", "applied", undefined],
      ["a3", "rejected", "the action id is used twice"],
    ]);
    expect((await open()).session!.exercises.map((e) => e.id)).toEqual(["e1", "e2"]);
  });

  it("a rebuild is a proposal: the open session is not changed (see coachProposal.test.ts)", async () => {
    await world();
    stubOpenAi(coach(() => ({ message: "New session.", actions: [{ id: "a1", name: "rebuild_open_session", arguments: { exercises: [BALANCE, { name: "Squat", sets: [{ reps: 5, kg: 60, max: false }] }], focus: "Balance" } }] })));
    await send("m1", "make the whole session about balance", { screen: "session", openSessionId: "s1" });
    await settle(t);
    expect(await open()).toMatchObject({ rev: 1, updatedBy: "app", session: { placeId: "p-gym", exercises: EXERCISES } });
    expect((await messages())[1]!.actions).toEqual([{ actionId: "a1", name: "rebuild_open_session", status: "drafted", detail: "Proposed: 2 exercises" }]);
  });
});

describe("question, context and the old path", () => {
  it("a question with quick answers is stored and returned by the messages query; nothing else is written", async () => {
    await world();
    stubOpenAi(coach(() => ({ message: "Does your gym have a balance board?", actions: [], question: { text: "Balance board at the Gym?", answers: [{ id: "yes", label: "Yes" }, { id: "no", label: "No" }] } })));
    await send("m1", "this exercise is odd", CONTEXT);
    await settle(t);
    expect((await messages())[1]).toMatchObject({ text: "Does your gym have a balance board?", actions: [], question: { text: "Balance board at the Gym?", answers: [{ id: "yes", label: "Yes" }, { id: "no", label: "No" }] } });
    expect((await open()).rev).toBe(1);
  });

  it("a send without context, or from the start screen, is a chat turn: the coach turn answers and no old reply runs", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await world();
    await send("m1", "hello");
    await send("m2", "hello again", { screen: "start" });
    await settle(t);
    const as = (await messages()).filter((m) => m.role === "assistant");
    expect(as).toHaveLength(2);
    for (const a of as) {
      expect(a.text).toBe("Mock coach: noted.");
      expect(a.actions).toEqual([]);
    }
    expect(as.map((a) => a.turnId)).toEqual(["m1", "m2"]);
    const calls = await t.run((c) => c.db.query("aiCalls").withIndex("by_job", (q) => q.eq("job", "coach_turn")).collect());
    expect(calls).toHaveLength(2);
    expect(await t.run((c) => c.db.query("aiCalls").withIndex("by_job", (q) => q.eq("job", "chat")).collect())).toHaveLength(0);
  });

  it("rejects a context id that is too long", async () => {
    await world();
    await expect(send("m1", "x", { screen: "session", openSessionId: "x".repeat(101) })).rejects.toThrow(/context.openSessionId/);
  });
});

describe("prompts say that place knowledge is partial", () => {
  it("coach_turn and learn_place", () => {
    const ct = coachTurnJob.build({ contextBlock: "CTX", history: [{ role: "user", content: "hi" }], turn: { screen: "session" }, limits: [] });
    expect(ct.system).toContain("never a full list");
    expect(ct.system).toContain("unknown, not missing");
    expect(ct.system).toContain("ONLY when the person asks to change the whole session");
    expect(ct.system).toContain("No function changes it");
    expect(ct.messages[0]!.content).toContain("INPUT_JSON:");
    expect(learnPlaceJob.build({ place: { name: "Gym", equipment: "" }, otherPlaces: [], sentence: "x" }).system).toContain("only when the person said so");
  });
});

describe("one prompt and the same data on every screen (owner's words 2026-11-24)", () => {
  const build = (screen: string) => coachTurnJob.build({ contextBlock: "CTX", history: [{ role: "user", content: "hi" }], turn: { screen }, limits: [] });
  it("the system prompt is the same on every screen and holds logging, drafts, programs, session and places", () => {
    const systems = ["log", "chat", "session", "exercise", "goal", "program"].map((x) => build(x).system);
    expect(new Set(systems).size).toBe(1);
    for (const w of ["draft_log", "propose_program", "rebuild_open_session", "update_place", "currentLogDraft", "categoriesInUse", "goalsYouMayChange"]) expect(systems[0]).toContain(w);
    expect(systems[0]).not.toContain("tell the person to use Log");
  });

  it("every screen gets today, the time now and the categories in use; the session tools work from the log chat thread", async () => {
    await world();
    await t.mutation(api.commands.entries.save, { token: TOKEN, entryId: "e0", text: "lunch", at: Date.now(), fileIds: [] }).catch(() => undefined);
    const calls = stubOpenAi(coach(() => ({ message: "Removed it.", actions: [{ id: "a1", name: "remove_open_exercise", arguments: { exerciseId: "e3" } }] })));
    await send("m1", "drop the leg press", { screen: "log", openSessionId: "s1" });
    await settle(t);
    await send("m2", "again", { screen: "chat" });
    await settle(t);
    for (const c of turns(calls)) expect(c.input).toMatchObject({ today: expect.any(String), now: expect.any(String) });
    expect((await open()).session!.exercises.map((e) => e.id)).toEqual(["e1", "e2"]);
  });

  it("photos of other entries are not sent; the photos of the entry in view are (aiCalls images)", async () => {
    await world();
    const storageId = await t.run((c) => c.storage.store(new Blob([new Uint8Array([1, 2, 3])], { type: "image/png" })));
    for (const id of ["p1", "p2", "p3"]) await t.mutation(api.commands.files.register, { token: TOKEN, fileId: id, storageId, name: `${id}.png`, mime: "image/png", size: 3 });
    const e = (entryId: string, fileIds: string[]) => t.mutation(api.commands.entries.save, { token: TOKEN, entry: { entryId, text: "x", fileIds, at: Date.now() - 3_600_000, createdAt: Date.now() - 3_600_000 } });
    await e("eA", ["p1", "p2"]);
    await e("eB", ["p3"]);
    stubOpenAi(coach(() => ({ message: "ok", actions: [] })));
    const images = async () => (await t.run((c) => c.db.query("aiCalls").withIndex("by_job", (q) => q.eq("job", "coach_turn")).order("desc").first()))!.images;
    await send("m1", "what do you know about my knee?", { screen: "chat" });
    await settle(t);
    expect(await images()).toBe(0);
    await send("m2", "what is in this entry?", { screen: "chat", entryId: "eA" });
    await settle(t);
    expect(await images()).toBe(2);
  });
});
