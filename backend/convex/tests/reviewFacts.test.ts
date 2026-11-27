import { describe, expect, it } from "vitest";
import { reviewFacts } from "../functions/model/reviewFacts";
import type { ProgramForCoach } from "../functions/model/programForCoach";
import type { Exercise, Session } from "../functions/model/schema";

/** ADR-041: the facts of a session are made in code, from the history. */
const DAY = 86_400_000;
const T0 = Date.UTC(2026, 10, 26, 10, 0, 0);
const ex = (name: string, sets: [number, number][], more: Partial<Exercise> = {}): Exercise => ({ name, sets: sets.map(([reps, kg]) => ({ reps, kg, max: false })), ...more }) as Exercise;
const sess = (id: string, daysAgo: number, exercises: Exercise[], more: Partial<Session> = {}): Session => {
  const end = T0 - daysAgo * DAY;
  return { id, kind: "gym", type: "Gym", focus: "Legs", startedAt: end - 60 * 60_000, endedAt: end, exercises, source: "app", ...more };
};

describe("facts per exercise", () => {
  const past = [sess("a", 10, [ex("Leg Press", [[12, 40], [12, 50]])]), sess("b", 3, [ex("Squat", [[5, 60]]), ex("leg  press", [[12, 55]])])];

  it("matches the same exercise with its date and best set, and signs the change", () => {
    const f = reviewFacts([...past, sess("c", 0, [ex("Leg Press", [[10, 60], [12, 55]])])], sess("c", 0, [ex("Leg Press", [[10, 60], [12, 55]])]), { timeZone: "UTC" });
    expect(f.exercises).toEqual([{ name: "Leg Press", bestToday: "10x60", firstTime: false, lastTime: { date: "2026-11-23", best: "12x55" }, change: "+5 kg", daysSinceLast: 3 }]);
  });

  it("says the same weight with more reps, a lower weight, and the same", () => {
    const base = [sess("a", 3, [ex("Row", [[8, 50]])])];
    const f = (sets: [number, number][]) => reviewFacts([...base, sess("c", 0, [ex("Row", sets)])], sess("c", 0, [ex("Row", sets)]), { timeZone: "UTC" }).exercises[0]!.change;
    expect(f([[10, 50]])).toBe("+2 reps at the same weight");
    expect(f([[8, 45]])).toBe("-5 kg");
    expect(f([[8, 50]])).toBe("same");
  });

  it("marks a first time, with no last time and no change", () => {
    const f = reviewFacts([...past, sess("c", 0, [ex("Deadlift", [[5, 80]])])], sess("c", 0, [ex("Deadlift", [[5, 80]])]), { timeZone: "UTC" });
    expect(f.exercises).toEqual([{ name: "Deadlift", bestToday: "5x80", firstTime: true }]);
  });

  it("does not match a different exercise by looks (Leg Extension is not Leg Press)", () => {
    const s = sess("c", 0, [ex("Leg Extension", [[10, 30]])]);
    expect(reviewFacts([...past, s], s).exercises[0]!.firstTime).toBe(true);
  });

  it("compares time exercises by minutes", () => {
    const bike = (m: number, id: string, d: number) => sess(id, d, [{ name: "Bike", measure: "time", sets: [{ minutes: m }] }]);
    const s = bike(25, "c", 0);
    const f = reviewFacts([bike(20, "a", 5), s], s, { timeZone: "UTC" });
    expect(f.exercises[0]).toMatchObject({ bestToday: "25 min", change: "+5 min", lastTime: { date: "2026-11-21", best: "20 min" } });
  });
});

describe("facts against the plan", () => {
  const planned = (sets: [number, number][]) => sets.map(([reps, kg]) => ({ reps, kg, max: false }));
  const s = sess("c", 0, [
    ex("Bench", [[8, 60], [8, 60], [8, 60]], { planned: planned([[8, 60], [8, 60], [8, 60]]) }),
    ex("Row", [[8, 50]], { planned: planned([[8, 50], [8, 50]]) }),
    ex("Curl", [[10, 20], [10, 20]], { planned: planned([[10, 15], [10, 15]]) }),
    ex("Face pull", [[15, 10]]),
  ], { planNote: "Push and pull", skipped: [{ name: "Dips", planned: planned([[10, 0], [10, 0]]) }] });

  it("says more, less or as planned with both numbers, lists skipped and added", () => {
    const a = reviewFacts([s], s).againstPlan!;
    expect(a.planNote).toBe("Push and pull");
    expect(a.exercises).toEqual([
      { name: "Bench", planned: "3 sets, top 8x60", done: "3 sets, top 8x60", verdict: "as planned" },
      { name: "Row", planned: "2 sets, top 8x50", done: "1 set, top 8x50", verdict: "less" },
      { name: "Curl", planned: "2 sets, top 10x15", done: "2 sets, top 10x20", verdict: "more" },
    ]);
    expect(a.skippedPlanned).toEqual([{ name: "Dips", planned: "2 sets, top 10x0" }]);
    expect(a.addedNotPlanned).toEqual(["Face pull"]);
  });

  it("has no plan block for a session with no plan", () => {
    const plain = sess("c", 0, [ex("Bench", [[8, 60]])]);
    expect(reviewFacts([plain], plain).againstPlan).toBeUndefined();
  });
});

describe("facts of the session and its usual", () => {
  const usualSessions = (n: number) => Array.from({ length: n }, (_, i) => sess(`u${i}`, 7 * (i + 1), [ex("Squat", [[5, 80], [5, 80], [5, 80], [5, 80]])]));

  it("gives the usual only with at least 3 such sessions in 8 weeks, and compares", () => {
    const s = sess("c", 0, [ex("Squat", [[5, 80]])], { startedAt: T0 - 20 * 60_000, endedAt: T0 });
    const f = reviewFacts([...usualSessions(3), s], s);
    expect(f.session).toMatchObject({ doneSets: 1, minutes: 20, usual: { sessions: 3, medianSets: 4, setsVsUsual: "fewer or shorter", medianMinutes: 60, durationVsUsual: "fewer or shorter" } });
  });

  it("hides the usual with fewer than 3 sessions, other focus, or older than 8 weeks", () => {
    const s = sess("c", 0, [ex("Squat", [[5, 80]])]);
    expect(reviewFacts([...usualSessions(2), s], s).session.usual).toBeUndefined();
    const other = usualSessions(5).map((x) => ({ ...x, focus: "Upper" }));
    expect(reviewFacts([...other, s], s).session.usual).toBeUndefined();
    const old = [sess("o1", 60, [ex("Squat", [[5, 80]])]), sess("o2", 70, [ex("Squat", [[5, 80]])]), sess("o3", 80, [ex("Squat", [[5, 80]])])];
    expect(reviewFacts([...old, s], s).session.usual).toBeUndefined();
  });

  it("says about the same inside 20 percent", () => {
    const s = sess("c", 0, [ex("Squat", [[5, 80], [5, 80], [5, 80], [5, 80]])]);
    expect(reviewFacts([...usualSessions(3), s], s).session.usual).toMatchObject({ setsVsUsual: "about the same", durationVsUsual: "about the same" });
    const longer = sess("d", 0, [ex("Squat", [[5, 80], [5, 80], [5, 80], [5, 80], [5, 80], [5, 80]])]);
    expect(reviewFacts([...usualSessions(3), longer], longer).session.usual!.setsVsUsual).toBe("more");
  });
});

describe("program, comments and the body log", () => {
  const program: ProgramForCoach = {
    programId: "p1", title: "Ski prep", purpose: "x", status: "active", startsOn: "2026-11-16", endsOn: "2026-12-13",
    week: ["A", "B", "A"], rules: [], tests: [],
    phases: [{ title: "Base", note: "", weekFrom: 1, weekTo: 4, sessions: [{ key: "A", title: "A", activity: "Gym", exercises: [] }, { key: "B", title: "B", activity: "Gym", exercises: [] }] }],
  } as never;

  it("gives the week x of y, the sessions done and planned this week, and the days to the end", () => {
    const s = sess("c", 0, [ex("Squat", [[5, 80]])], { programId: "p1", programWeek: 2, programSlot: 1, programKey: "A" });
    const earlier = sess("b", 2, [ex("Squat", [[5, 80]])], { programId: "p1", programWeek: 2, programSlot: 2, programKey: "B" });
    const f = reviewFacts([earlier, s], s, { programs: [program], timeZone: "UTC" });
    expect(f.program).toEqual([{ title: "Ski prep", week: "2 of 4", sessionsDoneThisWeek: 2, sessionsPlannedThisWeek: 3, daysToProgramEnd: 17 }]);
  });

  it("has no program block when no program runs", () => {
    const s = sess("c", 0, [ex("Squat", [[5, 80]])]);
    expect(reviewFacts([s], s, { programs: [{ ...program, status: "paused" }] }).program).toBeUndefined();
    expect(reviewFacts([s], s, { programs: [{ ...program, startsOn: "2027-01-01", endsOn: "2027-02-01" }] }).program).toBeUndefined();
  });

  it("keeps the comments, the note and the body log entries of the day word for word", () => {
    const s = sess("c", 0, [ex("Squat", [[5, 80]], { comment: "knee clicked" })], { note: "tired" });
    const entries = [
      { kind: "Body", text: "left knee a bit sore", at: T0 - 3 * 60 * 60_000 },
      { kind: "Meal", text: "pasta", at: T0 },
      { kind: "Body", text: "yesterday: back ache", at: T0 - DAY },
    ];
    const f = reviewFacts([s], s, { entries, timeZone: "UTC" });
    expect(f.commentsFromThePerson).toEqual([{ exercise: "Squat", text: "knee clicked" }]);
    expect(f.noteFromThePerson).toBe("tired");
    expect(f.bodyLogToday).toEqual([{ time: "07:00", text: "left knee a bit sore" }]);
  });

  it("leaves out body entries with empty text and entries that made a session", () => {
    const s = sess("c", 0, [ex("Squat", [[5, 80]])]);
    const entries = [
      { kind: "Body", text: "", at: T0 - 60_000 },
      { kind: "Body", text: "  ", at: T0 - 60_000 },
      { kind: "Body", text: "legs 3x10 then bike", at: T0 - 60_000, madeSession: true },
      { kind: "body", text: "shoulder tight", at: T0 - 120_000, madeSession: false },
    ];
    expect(reviewFacts([s], s, { entries, timeZone: "UTC" }).bodyLogToday).toEqual([{ time: "09:58", text: "shoulder tight" }]);
  });

  it("counts every finished session of the program week, linked to a slot or not, and the reviewed one", () => {
    // Program from Thu 2026-11-19; week 2 = 26 Nov to 2 Dec. Reviewed session on 26 Nov; two earlier ones on 24 and 25 Nov are week 1.
    const p = { ...program, startsOn: "2026-11-19", endsOn: "2026-12-16", week: ["A", "B", "A", "B", "A"] } as ProgramForCoach;
    const s = sess("c", 0, [ex("Squat", [[5, 80]])]);
    const a = sess("a", 2, [ex("Squat", [[5, 80]])]);
    const b = sess("b", 1, [ex("Squat", [[5, 80]])]);
    const f = reviewFacts([a, b, s], s, { programs: [p], timeZone: "UTC" });
    expect(f.program![0]).toMatchObject({ week: "2 of 4", sessionsDoneThisWeek: 1, sessionsPlannedThisWeek: 5 });
    // A second one on 27 Nov is after the reviewed day: not counted. One on 26 Nov before it is counted.
    const early = sess("e", 0, [ex("Row", [[5, 40]])], { startedAt: T0 - 5 * 3600_000, endedAt: T0 - 4 * 3600_000 });
    expect(reviewFacts([a, b, early, s], s, { programs: [p], timeZone: "UTC" }).program![0]!.sessionsDoneThisWeek).toBe(2);
  });
});
