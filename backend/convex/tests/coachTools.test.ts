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
    expect(removeOne(list, "c")).toMatchObject({ ok: false });
    expect(replaceOne(list, "b", planned("ex A"), "n1")).toMatchObject({ ok: false, reason: '"ex A" is in the session already' });
    expect(replaceOne(list, "zz", planned("Row"), "n1")).toMatchObject({ ok: false });
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
