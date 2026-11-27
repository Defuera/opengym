import { describe, expect, it } from "vitest";
import { CoachTurnSchema, editPlaceText } from "../functions/model/coachTools";
import { addOne, removeOne, replaceOne, type OpenExercise } from "../functions/model/openSession";
import { knowledgeOf } from "../functions/model/placeKnowledge";

const ex = (id: string, done = false, comment?: string): OpenExercise => ({ id, name: `Ex ${id}`, sets: [{ reps: 8, kg: 10, max: false, done }], fresh: false, carry: false, ...(comment ? { comment } : {}) });
const planned = (name: string) => ({ name, sets: [{ reps: 5, kg: 20 }] });

describe("one exercise at a time (ADR-032)", () => {
  const list = [ex("a", true), ex("b"), ex("c", false, "knee ok")];
  it("replace keeps the place in the list and every other exercise", () => {
    const r = replaceOne(list, "b", planned("Row"), "n1");
    expect(r.ok && r.exercises.map((e) => e.id)).toEqual(["a", "n1", "c"]);
    expect(r.ok && r.exercises[0]).toBe(list[0]);
  });
  it("never touches the person's work, nor a name already there", () => {
    expect(replaceOne(list, "a", planned("Row"), "n1")).toMatchObject({ ok: false });
    expect(replaceOne(list, "c", { name: "Ex c", sets: [{ reps: 5, kg: 20 }] }, "n1")).toMatchObject({ ok: true });
    expect(removeOne(list, "c")).toMatchObject({ ok: false });
    expect(replaceOne(list, "b", planned("ex A"), "n1")).toMatchObject({ ok: false, reason: '"ex A" is in the session already' });
    expect(replaceOne(list, "zz", planned("Row"), "n1")).toMatchObject({ ok: false });
  });
  it("replace on an exercise with done sets keeps every done set, in place, and replaces only the not-done ones", () => {
    const d = (reps: number, kg: number) => ({ reps, kg, max: false, done: true, at: 5 });
    const n = (reps: number, kg: number) => ({ reps, kg, max: false, done: false });
    const e: OpenExercise = { id: "g", name: "Glute Drive", sets: [d(12, 30), n(12, 40), d(10, 35), n(8, 40)], fresh: false, carry: false, comment: "knee" };
    const r = replaceOne([e], "g", { name: " glute drive ", note: "x", sets: [{ reps: 12, kg: 20 }] }, "new");
    expect(r.ok && r.exercises[0]).toEqual({ ...e, note: "x", sets: [d(12, 30), n(12, 20), d(10, 35)] });
    const more = replaceOne([e], "g", { name: "Glute Drive", sets: [{ reps: 1, kg: 1 }, { reps: 2, kg: 2 }, { reps: 3, kg: 3 }] }, "new");
    expect(more.ok && more.exercises[0]!.sets).toEqual([d(12, 30), n(1, 1), d(10, 35), n(2, 2), n(3, 3)]);
    expect(replaceOne([e], "g", { name: "Other", sets: [{ reps: 1, kg: 1 }] }, "new")).toMatchObject({ ok: false });
    expect(replaceOne([e], "g", { name: "Glute Drive", measure: "time", sets: [{ minutes: 1 }] }, "new")).toMatchObject({ ok: false });
  });
  it("replace drops coach sets that repeat the done sets at the start", () => {
    const d = (reps: number, kg: number) => ({ reps, kg, max: false, done: true, at: 5 });
    const n = (reps: number, kg: number) => ({ reps, kg, max: false, done: false });
    const sets = (x: { reps: number; kg: number }[]) => x;
    const ex = (done: ReturnType<typeof d>[]): OpenExercise => ({ id: "g", name: "Glute Drive", sets: done, fresh: false, carry: false });
    const run = (e: OpenExercise, coach: { reps: number; kg: number }[]) => {
      const r = replaceOne([e], "g", { name: "Glute Drive", sets: sets(coach) }, "new");
      return r.ok ? r.exercises[0]!.sets : r;
    };
    const A = { reps: 12, kg: 30 }, B = { reps: 10, kg: 35 }, C = { reps: 12, kg: 20 };
    expect(run(ex([d(12, 30), d(10, 35)]), [A, B, C])).toEqual([d(12, 30), d(10, 35), n(12, 20)]);
    expect(run(ex([d(12, 30), d(10, 35)]), [A, C])).toEqual([d(12, 30), d(10, 35), n(12, 20)]);
    expect(run(ex([d(12, 30), d(10, 35)]), [C])).toEqual([d(12, 30), d(10, 35), n(12, 20)]);
    expect(run(ex([d(12, 30)]), [A, C])).toEqual([d(12, 30), n(12, 20)]);
  });
  it("replace drops repeated done sets of a timed exercise", () => {
    const e: OpenExercise = { id: "r", name: "Run", measure: "time", sets: [{ minutes: 10, distanceKm: 2, done: true, at: 5 }], fresh: false, carry: false };
    const r = replaceOne([e], "r", { name: "Run", measure: "time", sets: [{ minutes: 10, distanceKm: 2 }, { minutes: 5 }] }, "new");
    expect(r.ok && r.exercises[0]!.sets).toEqual([{ minutes: 10, distanceKm: 2, done: true, at: 5 }, { minutes: 5, done: false }]);
  });
  it("add goes after the given id or at the end; remove takes one out", () => {
    const after = addOne(list, planned("Row"), "n1", "a");
    expect(after.ok && after.exercises.map((e) => e.id)).toEqual(["a", "n1", "b", "c"]);
    const end = addOne(list, planned("Row"), "n1");
    expect(end.ok && end.exercises.map((e) => e.id)).toEqual(["a", "b", "c", "n1"]);
    expect(addOne(list, planned("Row"), "n1", "zz")).toMatchObject({ ok: false });
    const rm = removeOne(list, "b");
    expect(rm.ok && rm.exercises.map((e) => e.id)).toEqual(["a", "c"]);
  });
});

describe("place text edits", () => {
  it("adds on a new line once, removes a phrase in any case", () => {
    expect(editPlaceText("", "Balance board")).toBe("Balance board");
    expect(editPlaceText("Rack", "Balance board")).toBe("Rack\nBalance board");
    expect(editPlaceText("Rack, balance board", "Balance board")).toBe("Rack, balance board");
    expect(editPlaceText("Rack\nNo balance board", "Balance board", "no balance board")).toBe("Rack\nBalance board");
    expect(editPlaceText("Rack, bike, bench", undefined, "bike")).toBe("Rack, bench");
  });
  it("knowledge: empty is unknown, any text is partial unless stored", () => {
    expect(knowledgeOf({ text: "" })).toBe("unknown");
    expect(knowledgeOf({ text: "Rack" })).toBe("partial");
    expect(knowledgeOf({ text: "Rack", knowledgeState: "unknown" })).toBe("unknown");
  });
});

describe("the coach turn shape", () => {
  it("knows only the tools of this step; actions default to none", () => {
    expect(CoachTurnSchema.parse({ message: "ok" })).toEqual({ message: "ok", actions: [] });
    expect(CoachTurnSchema.safeParse({ message: "ok", actions: [{ id: "a", name: "set_open_session_place", arguments: {} }] }).success).toBe(false);
    expect(CoachTurnSchema.safeParse({ message: "ok", actions: [{ id: "a", name: "update_place", arguments: { placeId: "p", evidence: "person_said" } }] }).success).toBe(false);
  });
});
