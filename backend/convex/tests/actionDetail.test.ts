import { beforeEach, describe, expect, it } from "vitest";
import { api, internal } from "../functions/_generated/api";
import { addDetail, cut, placeDetail, proposeDetail, removeDetail, replaceDetail } from "../functions/model/actionDetail";
import type { OpenExercise } from "../functions/model/openSession";
import { TOKEN, setup, type T } from "./helpers";

const old: OpenExercise = { id: "e2", name: "Balance Board", sets: [{ reps: 10, kg: 0, max: false, done: false }], note: "Easy" };

describe("detail lines (pure)", () => {
  it("replace with another name", () => expect(replaceDetail({ ...old, name: "Tandem Stand" }, { name: "Balance Board", sets: [{ reps: 10, kg: 0, max: false }] })).toBe("Tandem Stand → Balance Board"));
  it.each([
    [{ note: "Hard", sets: [{ reps: 10, kg: 0, max: false }] }, "Balance Board: note changed"],
    [{ note: "Easy", sets: [{ reps: 12, kg: 0, max: false }] }, "Balance Board: sets changed"],
    [{ note: "Hard", sets: [{ reps: 12, kg: 0, max: false }] }, "Balance Board: note and sets changed"],
    [{ note: "Easy", sets: [{ reps: 10, kg: 0, max: false }] }, "Balance Board: nothing changed"],
  ])("replace with the same name %j", (after, text) => expect(replaceDetail(old, { name: "balance board", ...after })).toBe(text.replace("Balance Board", "balance board")));
  it("add, remove, place, propose", () => {
    expect(addDetail({ name: "Wall Sit", measure: "time", sets: [{ minutes: 0.5 }, { minutes: 0.5 }, { minutes: 0.5 }] })).toBe("Added: Wall Sit, 3 × 30 s");
    expect(addDetail({ name: "Bench", sets: [{ reps: 8, kg: 40, max: false }, { reps: 8, kg: 40, max: false }] })).toBe("Added: Bench, 2 × 8 · 40 kg");
    expect(removeDetail({ ...old, name: "Brisk Walk" })).toBe("Removed: Brisk Walk");
    expect(placeDetail("Gym", "balance board")).toBe("Gym: added balance board");
    expect(placeDetail("Gym", undefined, "second bike")).toBe("Gym: removed second bike");
    expect(placeDetail("Gym", "a", "b")).toBe("Gym: added a, removed b");
    expect(proposeDetail(7)).toBe("Proposed: 7 exercises");
    expect(proposeDetail(1)).toBe("Proposed: 1 exercise");
  });
  it("is cut to 120", () => expect(cut("x".repeat(300))).toHaveLength(120));
});

describe("the executor sets detail", () => {
  let t: T;
  beforeEach(() => {
    t = setup();
  });
  it("on every kind of action, and not on a rejection", async () => {
    await t.mutation(api.commands.places.save, { token: TOKEN, placeId: "p-gym", name: "Gym", text: "Rack, second bike" });
    const ex = (id: string, name: string, note?: string): OpenExercise => ({ id, name, sets: [{ reps: 10, kg: 0, max: false, done: false }], fresh: false, carry: false, ...(note ? { note } : {}) });
    await t.mutation(api.commands.openSession.put, { token: TOKEN, session: { id: "s1", kind: "gym", type: "Gym", startedAt: 1000, placeId: "p-gym", exercises: [ex("e1", "Brisk Walk"), ex("e2", "Tandem Stand"), ex("e3", "Leg press", "Old")] } });
    await t.mutation(api.commands.threads.create, { token: TOKEN, threadId: "th1", title: "Coach" });
    await t.mutation(api.commands.messages.send, { token: TOKEN, threadId: "th1", messageId: "m1", text: "remove the second bike", context: { screen: "session", openSessionId: "s1" } });
    const set = { reps: 10, kg: 0, max: false };
    const actions = [
      { id: "a1", name: "update_place", arguments: { placeId: "p-gym", remove: "second bike", evidence: "person_said" } },
      { id: "a2", name: "remove_open_exercise", arguments: { exerciseId: "e1" } },
      { id: "a3", name: "replace_open_exercise", arguments: { exerciseId: "e2", exercise: { name: "Balance Board", sets: [set] } } },
      { id: "a4", name: "replace_open_exercise", arguments: { exerciseId: "e3", exercise: { name: "Leg press", note: "New", sets: [set, set] } } },
      { id: "a5", name: "add_open_exercise", arguments: { exercise: { name: "Wall Sit", measure: "time", sets: [{ minutes: 0.5 }, { minutes: 0.5 }, { minutes: 0.5 }] } } },
      { id: "a6", name: "remove_open_exercise", arguments: { exerciseId: "nope" } },
    ];
    const r = await t.mutation(internal.jobs.coachTurn.save, { userId: "owner", threadId: "th1", turnId: "m1", openSessionId: "s1", rev: 1, message: "x", actions, sources: [] });
    expect(r.map((x: { detail?: string }) => x.detail)).toEqual(["Gym: removed second bike", "Removed: Brisk Walk", "Tandem Stand → Balance Board", "Leg press: note and sets changed", "Added: Wall Sit, 3 × 30 s", undefined]);
    const ms = await t.query(api.queries.messages.list, { token: TOKEN, threadId: "th1" });
    expect(ms[1]!.actions![0]).toMatchObject({ detail: "Gym: removed second bike" });
  });
});

describe("the thread keeps the open session it was opened from", () => {
  it("is set by the first message with a session id, once, and listed", async () => {
    const t = setup();
    await t.mutation(api.commands.threads.create, { token: TOKEN, threadId: "th1", title: "Coach" });
    await t.mutation(api.commands.threads.create, { token: TOKEN, threadId: "th2", title: "Plain" });
    await t.mutation(api.commands.messages.send, { token: TOKEN, threadId: "th2", messageId: "p1", text: "hi", context: { screen: "chat" } });
    await t.mutation(api.commands.messages.send, { token: TOKEN, threadId: "th1", messageId: "m1", text: "a", context: { screen: "session", openSessionId: "s1" } });
    await t.mutation(api.commands.messages.send, { token: TOKEN, threadId: "th1", messageId: "m2", text: "b", context: { screen: "session", openSessionId: "s2" } });
    const list = await t.query(api.queries.threads.list, { token: TOKEN });
    expect(list.find((x) => x.threadId === "th1")!.openSessionId).toBe("s1");
    expect(list.find((x) => x.threadId === "th2")!.openSessionId).toBeUndefined();
  });
});
