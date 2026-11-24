import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "../functions/_generated/api";
import { formatSets } from "../functions/model/proposalText";
import type { OpenExercise } from "../functions/model/openSession";
import { TOKEN, setup, settle, stubOpenAi, type T } from "./helpers";

/** ADR-032: a change of the whole session is a proposal; the person approves it, and plain code applies it. */
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
  { id: "e2", name: "Single-leg stand", measure: "time", sets: [{ minutes: 1, done: false }], fresh: false, carry: false },
  { id: "e3", name: "Leg press", sets: [set(false), set(false)], fresh: false, carry: false },
];
const SESSION_CONTEXT = { screen: "session" as const, openSessionId: "s1" };
const PLAN = (n: number) => [
  { name: "Balance board stand", measure: "time", sets: [{ minutes: 0.5 }, { minutes: 0.5 }, { minutes: 0.5 }] },
  { name: "Squat", sets: [{ reps: 5, kg: 60, max: false }] },
  { name: `Calf raise ${n}`, sets: [{ reps: 12, kg: 0, max: false }, { reps: 12, kg: 0, max: false }, { reps: 12, kg: 0, max: false }] },
];
const rebuildTurn = (n = 1, model?: object) => ({
  message: "You want to change the whole workout to balance work. I propose this plan. Do you approve?",
  actions: [{ id: "a1", name: "rebuild_open_session", arguments: { title: "Balance day", exercises: PLAN(n), focus: "Balance" } }],
  ...(model ? { question: model } : {}),
});

async function world() {
  await t.mutation(api.commands.places.save, { token: TOKEN, placeId: "p-gym", name: "Gym", text: "Rack, barbell" });
  await t.mutation(api.commands.openSession.put, { token: TOKEN, session: { id: "s1", kind: "gym", type: "Gym", focus: "Legs", startedAt: 1000, placeId: "p-gym", exercises: EXERCISES } });
  await t.mutation(api.commands.threads.create, { token: TOKEN, threadId: "th1", title: "Coach" });
}
const send = (messageId: string, text: string, context?: object, answer?: { turnId: string; id: string }) =>
  t.mutation(api.commands.messages.send, { token: TOKEN, threadId: "th1", messageId, text, ...(context ? { context } : {}), ...(answer ? { answer } : {}) });
const open = () => t.query(api.queries.openSession.get, { token: TOKEN });
const messages = () => t.query(api.queries.messages.list, { token: TOKEN, threadId: "th1" });
const turns = (calls: { job: string }[]) => calls.filter((c) => c.job === "coach_turn");
const reply = (turn: () => object) => (job: string) => (job === "coach_turn" ? JSON.stringify(turn()) : job === "summarise_thread" ? JSON.stringify({ summary: "s" }) : "{}");
const lastAssistant = async () => (await messages()).filter((m) => m.role === "assistant").at(-1)!;

/** The person asks for a whole new workout; returns the provider calls. */
async function propose(n = 1, model?: object) {
  const calls = stubOpenAi(reply(() => rebuildTurn(n, model)));
  await send(`m${n}`, "I want to change the whole workout", SESSION_CONTEXT);
  await settle(t);
  return calls;
}

describe("a rebuild request is a proposal", () => {
  it("stores the proposal and the two fixed answers; the open session does not change", async () => {
    await world();
    // The model offers its own answers; the server replaces them.
    await propose(1, { text: "Shall I go on?", answers: [{ id: "yes", label: "Yes" }] });
    expect(await open()).toMatchObject({ rev: 1, updatedBy: "app", session: { focus: "Legs", exercises: EXERCISES } });
    const a = await lastAssistant();
    expect(a).toMatchObject({
      turnId: "m1",
      actions: [{ actionId: "a1", name: "rebuild_open_session", status: "drafted" }],
      question: { text: "Shall I go on?", answers: [{ id: "approve", label: "Approve" }, { id: "change", label: "Change something" }] },
      proposal: { title: "Balance day", state: "open", exercises: [{ name: "Balance board stand", sets: "3 × 30 s" }, { name: "Squat", sets: "1 × 5" }, { name: "Calf raise 1", sets: "3 × 12" }] },
    });
    expect(Object.keys(a.proposal!).sort()).toEqual(["exercises", "state", "title"]);
  });

  it("a proposal with no question from the model still gets a question with the two answers", async () => {
    await world();
    await propose();
    const q = (await lastAssistant()).question!;
    expect(q.text).toBe("Do you approve this plan?");
    expect(q.answers).toEqual([{ id: "approve", label: "Approve" }, { id: "change", label: "Change something" }]);
  });
});

describe("approve", () => {
  it("applies the proposal with no provider call and keeps the done sets", async () => {
    await world();
    const calls = await propose();
    const before = calls.length;
    await send("m2", "Approve", SESSION_CONTEXT, { turnId: "m1", id: "approve" });
    await settle(t);
    expect(calls).toHaveLength(before); // no new call of any job
    const r = await open();
    expect(r).toMatchObject({ rev: 2, updatedBy: "coach", session: { focus: "Balance", placeId: "p-gym" } });
    const names = r.session!.exercises.map((e) => e.name);
    expect(names).toEqual(["Squat", "Balance board stand", "Calf raise 1"]);
    expect(r.session!.exercises[0]).toEqual(EXERCISES[0]); // the done set stays exactly as it was
    const a = await lastAssistant();
    expect(a).toMatchObject({ role: "assistant", text: "Done. The session is rebuilt.", turnId: "m2" });
    expect((await messages()).find((m) => m.proposal)!.proposal!.state).toBe("applied");
    expect(await t.query(api.queries.threads.list, { token: TOKEN })).toMatchObject([{ status: "idle", pending: 0 }]);
  });

  it("makes no provider call at all", async () => {
    await world();
    await propose();
    const calls = stubOpenAi(reply(() => ({ message: "no", actions: [] })));
    await send("m2", "Approve", SESSION_CONTEXT, { turnId: "m1", id: "approve" });
    await settle(t);
    expect(calls).toHaveLength(0);
  });

  it("a second approve changes nothing", async () => {
    await world();
    await propose();
    await send("m2", "Approve", SESSION_CONTEXT, { turnId: "m1", id: "approve" });
    const once = await open();
    await send("m3", "Approve", SESSION_CONTEXT, { turnId: "m1", id: "approve" });
    await settle(t);
    expect(await open()).toEqual(once);
    expect(await lastAssistant()).toMatchObject({ turnId: "m3", actions: [{ status: "applied" }] });
  });

  it("a stale proposal (a newer one exists) is not applied and says why", async () => {
    await world();
    await propose(1);
    await propose(2);
    await send("m9", "Approve", SESSION_CONTEXT, { turnId: "m1", id: "approve" });
    await settle(t);
    expect(await open()).toMatchObject({ rev: 1, session: { exercises: EXERCISES } });
    const ms = await messages();
    expect(ms.filter((m) => m.proposal).map((m) => m.proposal!.state)).toEqual(["stale", "open"]);
    const a = await lastAssistant();
    expect(a.text).toContain("could not apply");
    expect(a.text).toContain("a newer proposal came after it");
    expect(a.actions).toMatchObject([{ status: "rejected", reason: "a newer proposal came after it" }]);
  });

  it("another open session makes it stale; no session says so", async () => {
    await world();
    await propose();
    await t.mutation(api.commands.openSession.put, { token: TOKEN, session: { id: "s2", kind: "gym", type: "Gym", startedAt: 5000, exercises: EXERCISES } });
    expect((await messages()).find((m) => m.proposal)!.proposal!.state).toBe("stale");
    await send("m2", "Approve", SESSION_CONTEXT, { turnId: "m1", id: "approve" });
    expect((await lastAssistant()).text).toContain("another session is open now");
    await t.mutation(api.commands.openSession.clear, { token: TOKEN, id: "s2" });
    await send("m3", "Approve", SESSION_CONTEXT, { turnId: "m1", id: "approve" });
    expect((await lastAssistant()).text).toContain("no session is open now");
  });
});

describe("change and other answers", () => {
  it("\"change\" runs a normal coach turn with the text", async () => {
    await world();
    const calls = await propose();
    const n = turns(calls).length;
    await send("m2", "Change something: fewer calf raises", SESSION_CONTEXT, { turnId: "m1", id: "change" });
    await settle(t);
    expect(turns(calls)).toHaveLength(n + 1);
    expect(await open()).toMatchObject({ rev: 1 });
    expect((await messages()).filter((m) => m.proposal)).toHaveLength(2); // the model proposed again
  });

  it("an approve with no stored proposal runs a normal turn", async () => {
    await world();
    const calls = stubOpenAi(reply(() => ({ message: "Nothing to approve here.", actions: [] })));
    await send("m1", "Approve", SESSION_CONTEXT, { turnId: "nope", id: "approve" });
    await settle(t);
    expect(turns(calls)).toHaveLength(1);
    expect((await lastAssistant()).text).toBe("Nothing to approve here.");
  });
});

describe("formatSets", () => {
  const reps = (...r: number[]) => ({ name: "x", sets: r.map((n) => ({ reps: n, kg: 0, max: false })) });
  const time = (...m: number[]) => ({ name: "x", measure: "time" as const, sets: m.map((minutes) => ({ minutes })) });
  it.each([
    [reps(10, 10, 10), "3 × 10"],
    [reps(10, 8, 6), "10, 8, 6"],
    [{ name: "x", sets: [{ reps: 0, kg: 20, max: true }, { reps: 0, kg: 20, max: true }] }, "2 × max"],
    [time(0.5, 0.5, 0.5), "3 × 30 s"],
    [time(10), "10 min"],
    [time(2, 2), "2 × 2 min"],
    [time(2, 1), "2 min, 1 min"],
    [time(1.5), "1.5 min"],
    [{ name: "x", sets: [] }, ""],
  ])("%j", (e, text) => expect(formatSets(e as never)).toBe(text));
});
