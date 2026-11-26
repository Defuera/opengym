import { beforeEach, describe, expect, it } from "vitest";
import { api, internal } from "../functions/_generated/api";
import { mergePlan, type OpenExercise } from "../functions/model/openSession";
import { setup, type T, TOKEN } from "./helpers";

/** ADR-028: the open session is one row; the app writes it; an outside writer changes only what is not done. */
const ex = (name: string, done: boolean[]): OpenExercise => ({ id: `id-${name}`, name, sets: done.map((d) => ({ reps: 12, kg: 30, max: false, done: d })), fresh: false, carry: false });
const open = (id: string, exercises: OpenExercise[]) => ({ id, kind: "gym" as const, type: "Gym", focus: "Legs", startedAt: 1000, source: "app", exercises });

describe("mergePlan", () => {
  const ids = () => {
    let n = 0;
    return () => `n${n++}`;
  };
  it("keeps an exercise with a done set and replaces the rest", () => {
    const out = mergePlan([ex("Bike", [true]), ex("Walk", [false]), ex("Leg Press", [true, false])], [{ name: "Squat", sets: [{ reps: 10, kg: 0 }] }], ids());
    expect(out.map((e) => e.name)).toEqual(["Bike", "Leg Press", "Squat"]);
    expect(out[1]).toEqual(ex("Leg Press", [true, false]));
    expect(out[2]).toMatchObject({ id: "n0", sets: [{ reps: 10, kg: 0, max: false, done: false }] });
  });
  it("keeps an exercise the person commented on, even with no done set", () => {
    const out = mergePlan([{ ...ex("Bike", [false]), comment: "level 9, HR 140" }, ex("Walk", [false])], [{ name: "Squat", sets: [{ reps: 10, kg: 0 }] }], ids());
    expect(out.map((e) => e.name)).toEqual(["Bike", "Squat"]);
    expect(out[0]!.comment).toBe("level 9, HR 140");
  });

  it("leaves out a planned exercise with the name of a kept one, and one with no set", () => {
    const out = mergePlan([ex("Leg Press", [true])], [{ name: " leg  press ", sets: [{ reps: 12, kg: 35 }] }, { name: "Empty", sets: [] }, { name: "Bike", measure: "time", sets: [{ minutes: 30 }] }], ids());
    expect(out.map((e) => e.name)).toEqual(["Leg Press", "Bike"]);
    expect(out[1]).toMatchObject({ measure: "time", sets: [{ minutes: 30, done: false }] });
  });
});

describe("the open session row", () => {
  let t: T;
  beforeEach(() => {
    t = setup();
  });
  const put = (id: string, exercises: OpenExercise[]) => t.mutation(api.commands.openSession.put, { token: TOKEN, session: open(id, exercises) });
  const get = () => t.query(api.queries.openSession.get, { token: TOKEN });

  it("is empty at first, then holds what the app put; a second put replaces it", async () => {
    expect(await get()).toMatchObject({ session: null, rev: 0 });
    expect(await put("a", [ex("Bike", [false])])).toBe(1);
    expect(await put("b", [ex("Row", [false])])).toBe(2);
    const r = await get();
    expect(r).toMatchObject({ rev: 2, updatedBy: "app", session: { id: "b", type: "Gym", exercises: [{ name: "Row" }] } });
    expect(await t.run((c) => c.db.query("openSession").collect())).toHaveLength(1);
  });

  it("clear removes only the session with that id", async () => {
    await put("a", [ex("Bike", [false])]);
    await t.mutation(api.commands.openSession.clear, { token: TOKEN, id: "other" });
    expect((await get()).session).not.toBeNull();
    await t.mutation(api.commands.openSession.clear, { token: TOKEN, id: "a" });
    await t.mutation(api.commands.openSession.clear, { token: TOKEN, id: "a" });
    expect((await get()).session).toBeNull();
  });

  it("an outside plan keeps the done work, raises rev and names the writer", async () => {
    await put("a", [ex("Bike", [true]), ex("Walk", [false])]);
    const rev = await t.mutation(internal.jobs.openSession.replacePlan, { userId: "owner", id: "a", by: "owner", focus: "Legs", exercises: [{ name: "Squat", sets: [{ reps: 10, kg: 0 }] }] });
    expect(rev).toBe(2);
    const r = await get();
    expect(r).toMatchObject({ rev: 2, updatedBy: "owner" });
    expect(r.session!.exercises.map((e) => e.name)).toEqual(["Bike", "Squat"]);
    expect(r.session!.exercises[0]!.sets[0]!.done).toBe(true);
  });

  it("an outside plan changes nothing with no open session or another id", async () => {
    expect(await t.mutation(internal.jobs.openSession.replacePlan, { userId: "owner", by: "coach", exercises: [] })).toBeNull();
    await put("a", [ex("Bike", [false])]);
    expect(await t.mutation(internal.jobs.openSession.replacePlan, { userId: "owner", id: "zzz", by: "coach", exercises: [] })).toBeNull();
    expect((await get()).rev).toBe(1);
  });

  it("needs the token and rejects too many exercises", async () => {
    await expect(t.query(api.queries.openSession.get, { token: "bad" })).rejects.toThrow(/unauthorized/);
    await expect(put("a", Array.from({ length: 41 }, (_, i) => ex(`E${i}`, [false])))).rejects.toThrow(/at most 40/);
  });
});
