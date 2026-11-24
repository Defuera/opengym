import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "../functions/_generated/api";
import { goalFromText, mergeRules } from "../functions/model/goalDraft";
import { TOKEN, pushSession, setup, settle, stubOpenAi, type T } from "./helpers";

/** ADR-032, step D: a goal, a limit and a note are drafted in any chat; Done writes them in plain code, once, with no entry. */
const NOW = Date.UTC(2026, 10, 24, 10);
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

const world = () => t.mutation(api.commands.threads.create, { token: TOKEN, threadId: "th1", title: "Chat" });
const send = (messageId: string, text: string, context: object, answer?: { turnId: string; id: string }) =>
  t.mutation(api.commands.messages.send, { token: TOKEN, threadId: "th1", messageId, text, context, ...(answer ? { answer } : {}) });
const done = (messageId: string, turnId: string, context: object) => send(messageId, "Done", context, { turnId, id: "approve" });
const messages = () => t.query(api.queries.messages.list, { token: TOKEN, threadId: "th1" });
const lastAssistant = async () => (await messages()).filter((m) => m.role === "assistant").at(-1)!;
const table = <N extends "goals" | "limits" | "context" | "entries" | "sessions">(n: N) => t.run((c) => c.db.query(n).collect());
const reply = (turn: () => object) => (job: string) => (job === "coach_turn" ? JSON.stringify(turn()) : job === "summarise_thread" ? JSON.stringify({ summary: "s" }) : "{}");
const draft = (args: object, message = "Here is the draft.") => ({ message, actions: [{ id: "a1", name: "draft_log", arguments: args }] });
const GOAL = { title: "Bench press 70 kg by spring", kind: "strength", exercise: "bench press", targetKg: 70 };
const LIMIT = { part: "left_knee", title: "Left knee", status: "active", rules: [{ kind: "avoid", text: "No deep squats", exercises: ["Deep squat"] }] };

describe("a goal draft", () => {
  it("the general chat runs the coach turn; the goal is drafted, then written once on Done with the structure of the log's spelling", async () => {
    await world();
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: pushSession("s1", NOW - 86_400_000) });
    const calls = stubOpenAi(reply(() => draft({ summary: "Bench 70 kg", goal: GOAL })));
    await send("m1", "I want to bench 70 kg by spring", { screen: "goal" });
    await settle(t);
    expect(calls.filter((c) => c.job === "coach_turn")).toHaveLength(1);
    const a = await lastAssistant();
    expect(a).toMatchObject({ turnId: "m1", actions: [{ name: "draft_log", status: "drafted" }], question: { answers: [{ id: "approve", label: "Done" }, { id: "change", label: "Add or change" }] }, proposal: { type: "log", noEntry: true, kind: "Goal", state: "open", goal: { title: GOAL.title, kind: "strength", targetKg: 70 } } });
    expect(await table("goals")).toHaveLength(0);
    await done("m2", "m1", { screen: "goal" });
    await done("m3", "m1", { screen: "goal" });
    await settle(t);
    const goals = await table("goals");
    expect(goals).toHaveLength(1);
    expect(goals[0]).toMatchObject({ title: GOAL.title, kind: "strength", targetKg: 70, status: "active", source: "ai" });
    expect(await table("entries")).toHaveLength(0);
    const texts = (await messages()).filter((m) => m.role === "assistant").map((m) => m.text);
    expect(texts[1]).toBe("Goal added.");
    expect(texts[2]).toContain("already");
    expect(calls.filter((c) => c.job === "coach_turn")).toHaveLength(1);
  });

  it("an exercise that is not in the log is dropped, as the old goal reading did", async () => {
    await world();
    stubOpenAi(reply(() => draft({ summary: "Pistol squat", goal: { title: "Pistol squat", kind: "strength", exercise: "Pistol squat" } })));
    await send("m1", "pistol squat", { screen: "chat" });
    await settle(t);
    const p = (await lastAssistant()).proposal as { goal: object };
    expect(p.goal).toEqual({ title: "Pistol squat", kind: "strength" });
  });

  it("a draft of a goal changes an existing goal by id: Done changes it, a repeat does nothing, and a goal that is gone is not brought back", async () => {
    await world();
    await t.mutation(api.commands.goals.create, { token: TOKEN, goalId: "g1", title: "Bench 60 kg", kind: "strength", targetKg: 60 });
    stubOpenAi(reply(() => draft({ summary: "Bench 70", goal: { title: "Bench 70 kg", kind: "strength", targetKg: 70 }, edits: { goalId: "g1" } })));
    await send("m1", "make it 70", { screen: "goal", goalId: "g1" });
    await settle(t);
    expect((await lastAssistant()).proposal).toMatchObject({ edits: { goalId: "g1" }, noEntry: true });
    await done("m2", "m1", { screen: "goal" });
    await done("m3", "m1", { screen: "goal" });
    expect(await table("goals")).toMatchObject([{ goalId: "g1", title: "Bench 70 kg", targetKg: 70 }]);
    expect((await messages()).filter((m) => m.role === "assistant")[1]!.text).toBe("Goal changed.");
    // The row is gone before the next draft: the part is dropped and the draft is rejected.
    await t.mutation(api.commands.goals.remove, { token: TOKEN, goalId: "g1" });
    await send("m4", "again", { screen: "goal" });
    await settle(t);
    const a = await lastAssistant();
    expect(a.actions![0]).toMatchObject({ status: "rejected", reason: "The goal to change is gone." });
    expect(a.proposal).toBeUndefined();
    expect(await table("goals")).toHaveLength(0);
  });

  it("with no AI the goal chat drafts the person's words as a custom goal (kg and times a week read by code); Done writes it", async () => {
    await world();
    await send("m1", "Squat 100 kg and train 3 times a week", { screen: "goal" });
    await settle(t);
    const a = await lastAssistant();
    expect(a.text).toContain("not available");
    expect(a.proposal).toMatchObject({ type: "log", noEntry: true, goal: { title: "Squat 100 kg and train 3 times a week", kind: "custom", targetKg: 100, sessionsPerWeek: 3 } });
    await done("m2", "m1", { screen: "goal" });
    expect(await table("goals")).toMatchObject([{ kind: "custom", targetKg: 100, sessionsPerWeek: 3 }]);
  });

  it("the mock provider drafts a goal", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await world();
    await send("m1", "bench 80 kg", { screen: "goal" });
    await settle(t);
    expect((await lastAssistant()).proposal).toMatchObject({ goal: { title: "bench 80 kg", targetKg: 80 } });
  });
});

describe("a limit draft", () => {
  it("is never written before Done; Done writes it once with no entry", async () => {
    await world();
    stubOpenAi(reply(() => draft({ summary: "Left knee", limit: LIMIT })));
    await send("m1", "my left knee hurts when I squat deep", { screen: "limit", part: "left_knee" });
    await settle(t);
    expect((await lastAssistant()).proposal).toMatchObject({ kind: "Limit", limit: { part: "left_knee", status: "active" } });
    expect(await table("limits")).toHaveLength(0);
    await done("m2", "m1", { screen: "limit" });
    await done("m3", "m1", { screen: "limit" });
    expect(await table("limits")).toMatchObject([{ part: "left_knee", title: "Left knee", rules: [{ kind: "avoid", text: "No deep squats", exercises: ["Deep squat"] }] }]);
    expect(await table("entries")).toHaveLength(0);
    expect((await messages()).filter((m) => m.role === "assistant")[1]!.text).toBe("Limit added.");
  });

  it("a change keeps the stored exercises of an unchanged rule, the records and the check-ins", async () => {
    await world();
    await t.mutation(api.commands.limits.save, { token: TOKEN, limit: { limitId: "l1", part: "left_knee", title: "Left knee", status: "active", rules: [{ kind: "avoid", text: "No deep squats", exercises: ["Deep squat"] }] } });
    await t.mutation(api.commands.limits.addRecord, { token: TOKEN, record: { recordId: "r1", limitId: "l1", title: "MRI", text: "words" } });
    const calls = stubOpenAi(reply(() => draft({ summary: "better", limit: { ...LIMIT, status: "improving", rules: [{ kind: "avoid", text: "No deep squats" }, { kind: "light", text: "Short runs" }] }, edits: { limitId: "l1" } })));
    await send("m1", "the knee is better", { screen: "limit", limitId: "l1" });
    await settle(t);
    const input = JSON.stringify(calls.find((c) => c.job === "coach_turn")!.input ?? calls);
    expect(input).not.toContain("words");
    await done("m2", "m1", { screen: "limit" });
    expect(await table("limits")).toMatchObject([{ limitId: "l1", status: "improving", rules: [{ kind: "avoid", text: "No deep squats", exercises: ["Deep squat"] }, { kind: "light", text: "Short runs" }] }]);
    expect(await t.run((c) => c.db.query("records").collect())).toHaveLength(1);
  });

  it("an invalid part is refused after one retry: no draft", async () => {
    await world();
    const calls = stubOpenAi(reply(() => draft({ summary: "x", limit: { ...LIMIT, part: "elbow of doom" } })));
    await send("m1", "x", { screen: "limit" });
    await settle(t);
    expect(calls.filter((c) => c.job === "coach_turn")).toHaveLength(2);
    expect((await lastAssistant()).proposal).toBeUndefined();
    expect(await table("limits")).toHaveLength(0);
  });
});

describe("a note draft", () => {
  it("is written once on Done; a change draft patches the note", async () => {
    await world();
    stubOpenAi(reply(() => draft({ summary: "warm up", note: { text: "Always warm up 10 minutes", topic: "warm-up" } })));
    await send("m1", "I always warm up for 10 minutes", { screen: "note" });
    await settle(t);
    await done("m2", "m1", { screen: "note" });
    await done("m3", "m1", { screen: "note" });
    const [n] = await table("context");
    expect(await table("context")).toHaveLength(1);
    expect(n).toMatchObject({ text: "Always warm up 10 minutes", topic: "warm-up", active: true, source: "ai" });
    stubOpenAi(reply(() => draft({ summary: "warm up", note: { text: "Warm up 5 minutes", topic: "warm-up" }, edits: { noteId: n!.itemId } })));
    await send("m4", "make it 5", { screen: "note", noteId: n!.itemId });
    await settle(t);
    await done("m5", "m4", { screen: "note" });
    expect(await table("context")).toMatchObject([{ itemId: n!.itemId, text: "Warm up 5 minutes" }]);
  });
});

describe("outside the log chat", () => {
  it("a draft with no goal, limit or note is rejected; a session part is left out; nothing is written", async () => {
    await world();
    stubOpenAi(reply(() => draft({ kind: "Meal", summary: "pasta" })));
    await send("m1", "I ate pasta", { screen: "chat" });
    await settle(t);
    const a = await lastAssistant();
    expect(a.actions![0]).toMatchObject({ status: "rejected" });
    expect(a.actions![0]!.reason).toContain("Log");
    expect(a.proposal).toBeUndefined();
    expect(await table("entries")).toHaveLength(0);
  });

  it("a session part is dropped but the goal stays", async () => {
    await world();
    stubOpenAi(reply(() => draft({ summary: "run goal", goal: { title: "Run 5 km", kind: "custom" }, session: { kind: "activity", type: "Run", minutes: 30 } })));
    await send("m1", "I ran and want to run 5 km", { screen: "chat" });
    await settle(t);
    const a = await lastAssistant();
    expect(a.actions![0]!.detail).toContain("left out");
    expect((a.proposal as { session?: unknown }).session).toBeUndefined();
  });

  it("no action deletes: an unknown delete function is an invalid action", async () => {
    await world();
    stubOpenAi(reply(() => ({ message: "Deleted.", actions: [{ id: "a1", name: "delete_goal", arguments: { goalId: "g1" } }] })));
    await t.mutation(api.commands.goals.create, { token: TOKEN, goalId: "g1", title: "Keep me", kind: "custom" });
    await send("m1", "delete my goal", { screen: "goal" });
    await settle(t);
    expect(await table("goals")).toHaveLength(1);
  });
});

describe("pure helpers", () => {
  it("goalFromText reads numbers only when they are there", () => {
    expect(goalFromText("Be strong")).toEqual({ title: "Be strong", kind: "custom" });
    expect(goalFromText("Deadlift 140,5 kg, 4x per week")).toMatchObject({ targetKg: 140.5, sessionsPerWeek: 4 });
  });
  it("mergeRules keeps the exercises of a rule the coach resent without them", () => {
    expect(mergeRules([{ kind: "avoid", text: "a", exercises: ["x"] }], [{ kind: "avoid", text: "a" }, { kind: "light", text: "b" }])).toEqual([{ kind: "avoid", text: "a", exercises: ["x"] }, { kind: "light", text: "b" }]);
  });
});
