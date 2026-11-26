import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "../functions/_generated/api";
import { toOpenExercise } from "../functions/model/openSession";
import { TOKEN, pushSession, setup, type T } from "./helpers";

/** ADR-041: a finished session keeps the plan it started from, so the coach can judge it. */
let t: T;
beforeEach(() => {
  vi.useFakeTimers();
  t = setup();
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

describe("the plan kept with a session", () => {
  it("stores and returns planNote, planned sets, the note of the exercise and skipped exercises", async () => {
    const base = pushSession("p1", 5_000_000);
    const session = {
      ...base,
      planNote: "Push day, bench first",
      exercises: [
        { ...base.exercises[0]!, planned: [{ reps: 6, kg: 40, max: false }, { reps: 6, kg: 45, max: false }], planNote: "Add 2.5 kg" },
        { name: "Bike", measure: "time" as const, sets: [{ minutes: 20 }], planned: [{ minutes: 30 }] },
      ],
      skipped: [{ name: "Dips", planned: [{ reps: 10, kg: 0, max: false }] }],
    };
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session });
    const [got] = await t.query(api.queries.sessions.recent, { token: TOKEN });
    expect(got!.planNote).toBe("Push day, bench first");
    expect(got!.exercises[0]).toMatchObject({ planned: [{ reps: 6, kg: 40, max: false }, { reps: 6, kg: 45, max: false }], planNote: "Add 2.5 kg" });
    expect(got!.exercises[1]).toMatchObject({ planned: [{ minutes: 30 }] });
    expect(got!.skipped).toEqual([{ name: "Dips", planned: [{ reps: 10, kg: 0, max: false }] }]);
  });

  it("a session with no plan works and has none", async () => {
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: pushSession("p2", 5_000_000) });
    const [got] = await t.query(api.queries.sessions.recent, { token: TOKEN });
    expect(got!.planNote).toBeUndefined();
    expect(got!.skipped).toBeUndefined();
    expect(got!.exercises[0]!.planned).toBeUndefined();
  });

  it("rejects a bad planned set", async () => {
    const base = pushSession("p3", 5_000_000);
    const bad = { ...base, exercises: [{ ...base.exercises[0]!, planned: [{ reps: 500, kg: 40, max: false }] }] };
    await expect(t.mutation(api.commands.sessions.save, { token: TOKEN, session: bad })).rejects.toThrow();
  });

  it("an exercise that enters the open session keeps its planned sets", () => {
    const e = toOpenExercise({ name: "Leg Press", note: "slow", sets: [{ reps: 12, kg: 30 }] }, "x1");
    expect(e.planned).toEqual([{ reps: 12, kg: 30, max: false }]);
    expect(e.sets[0]).toMatchObject({ reps: 12, kg: 30, done: false });
  });
});
