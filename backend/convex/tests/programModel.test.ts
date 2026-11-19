import { afterEach, describe, expect, it, vi } from "vitest";
import { checkProgramValue, fillKg, localDate, programNow, programPosition, programWeeks } from "../functions/model/program";
import { approvalFor } from "../functions/model/proposalPolicy";
import type { Exercise, Limit, PlanExercise, ProgramPhase, ProgramValue } from "../functions/model/schema";

const ex = (name: string, kg = 0): PlanExercise => ({ name, sets: [{ reps: 8, kg, max: false }, { reps: 8, kg, max: false }] });
const phase = (weekFrom: number, weekTo: number, keys = ["A", "B"]): ProgramPhase => ({
  title: `Weeks ${weekFrom}-${weekTo}`,
  weekFrom,
  weekTo,
  note: "",
  sessions: keys.map((key) => ({ key, title: `Session ${key}`, activity: "Gym", exercises: [ex("Squat", 40)] })),
});
/** 19 Nov to 2 Dec: 14 days, two weeks. */
const value = (over: Partial<ProgramValue> = {}): ProgramValue => ({
  title: "Knee for skiing",
  purpose: "Be ready by December",
  startsOn: "2026-11-19",
  endsOn: "2026-12-02",
  week: ["A", "B", "A"],
  phases: [phase(1, 1), phase(2, 2)],
  rules: [],
  tests: [],
  ...over,
});
const knee: Limit = { limitId: "k", part: "left_knee", title: "Knee", status: "active", rules: [{ kind: "avoid", text: "No deep squats", exercises: ["Squat"] }] };

afterEach(() => vi.unstubAllEnvs());

describe("programWeeks", () => {
  it("counts both days and rounds up", () => {
    expect(programWeeks("2026-12-01", "2026-12-07")).toBe(1);
    expect(programWeeks("2026-12-01", "2026-12-08")).toBe(2);
    expect(programWeeks("2026-11-19", "2026-12-02")).toBe(2);
    expect(programWeeks("2026-02-30", "2026-03-10")).toBeNull();
    expect(programWeeks("2026-12-02", "2026-12-01")).toBeNull();
  });
});

describe("checkProgramValue", () => {
  it("accepts a good program", () => {
    expect(checkProgramValue(value(), [])).toBeNull();
  });

  it("rejects dates that are not real, or an end before the start", () => {
    expect(checkProgramValue(value({ startsOn: "2026-02-30" }), [])).toMatch(/startsOn.*not a real date/);
    expect(checkProgramValue(value({ endsOn: "2026-13-01" }), [])).toMatch(/endsOn.*not a real date/);
    expect(checkProgramValue(value({ endsOn: "2026-11-18" }), [])).toMatch(/not end before/);
  });

  it("allows 26 weeks and rejects 27", () => {
    const long = (weeks: number, endsOn: string) => value({ endsOn, phases: [phase(1, weeks)] });
    expect(checkProgramValue(long(26, "2027-05-17"), [])).toBeNull(); // 26 * 7 = 182 days from 19 Nov
    expect(checkProgramValue(long(27, "2027-05-24"), [])).toMatch(/at most 26 weeks/);
  });

  it("needs phases in order, from week 1, with no gap, no overlap and every week covered", () => {
    expect(checkProgramValue(value({ phases: [phase(2, 2), phase(1, 1)] }), [])).toMatch(/phases\[0\].*no phase covers week 1/);
    expect(checkProgramValue(value({ phases: [phase(1, 1)] }), [])).toMatch(/cover 1 weeks but the program has 2/);
    expect(checkProgramValue(value({ phases: [phase(1, 2), phase(2, 2)] }), [])).toMatch(/phases\[1\].*already in an earlier phase/);
    expect(checkProgramValue(value({ endsOn: "2026-12-09", phases: [phase(1, 1), phase(3, 3)] }), [])).toMatch(/phases\[1\].*no phase covers week 2/);
    expect(checkProgramValue(value({ phases: [phase(1, 2), phase(3, 3)] }), [])).toMatch(/cover 3 weeks but the program has 2/);
    expect(checkProgramValue(value({ phases: [{ ...phase(1, 1), weekTo: 0 }, phase(2, 2)] }), [])).toMatch(/weekTo must not be before weekFrom/);
  });

  it("lets a phase leave a session of the week out, but not a key that no phase has; keys are unique inside a phase", () => {
    expect(checkProgramValue(value({ phases: [phase(1, 1), phase(2, 2, ["A"])] }), [])).toBeNull();
    expect(checkProgramValue(value({ week: ["A", "C"] }), [])).toMatch(/week lists "C"/);
    const fill = (x: { exercises: PlanExercise[] }) => x.exercises;
    // Week 2 has only A: the slots are the two A of the week, numbered by their place in `week` (1 and 3).
    const taper = { ...value({ phases: [phase(1, 1), phase(2, 2, ["A"])] }), status: "active" as const };
    expect(programNow(taper, "2026-11-27", () => false, fill).slots.map((x) => [x.slot, x.key])).toEqual([[1, "A"], [3, "A"]]);
    // A phase with none of the week's keys offers its own sessions in the order written.
    const own = { ...value({ phases: [phase(1, 1), phase(2, 2, ["Easy", "Rest"])] }), status: "active" as const };
    expect(programNow(own, "2026-11-27", (_w, slot) => slot === 1, fill).next).toMatchObject({ slot: 2, key: "Rest" });
    expect(checkProgramValue(value({ phases: [phase(1, 1, ["A", "B", "A"]), phase(2, 2)] }), [])).toMatch(/phases\[0\].*"A" is used twice/);
  });

  it("rejects an exercise that a limit marks avoid, in any phase", () => {
    expect(checkProgramValue(value(), [knee])).toMatch(/"Squat" is marked avoid/);
    expect(checkProgramValue(value(), [{ ...knee, status: "cleared" }])).toBeNull();
  });
});

describe("week and slots", () => {
  const p = (status: "active" | "paused" | "done" = "active") => ({ ...value(), status });
  const none = () => false;
  const fill = (s: { exercises: PlanExercise[] }) => s.exercises;

  it("is before, running or ended, with the week clamped to 1..weeks", () => {
    expect(programPosition(value(), "2026-11-18")).toMatchObject({ state: "before", week: 1, weeks: 2, phaseIndex: 0 });
    expect(programPosition(value(), "2026-11-19")).toMatchObject({ state: "running", week: 1, phaseIndex: 0 });
    expect(programPosition(value(), "2026-11-25")).toMatchObject({ state: "running", week: 1 });
    expect(programPosition(value(), "2026-11-26")).toMatchObject({ state: "running", week: 2, phaseIndex: 1 });
    expect(programPosition(value(), "2026-12-02")).toMatchObject({ state: "running", week: 2 });
    expect(programPosition(value(), "2026-12-03")).toMatchObject({ state: "ended", week: 2, phaseIndex: 1 });
  });

  it("numbers slots from 1 in week order, a repeated key A,B,A makes three slots, and next is the first not done", () => {
    const now = programNow(p(), "2026-11-20", (w, s) => w === 1 && s === 1, fill);
    expect(now.slots).toEqual([
      { slot: 1, key: "A", title: "Session A", done: true },
      { slot: 2, key: "B", title: "Session B", done: false },
      { slot: 3, key: "A", title: "Session A", done: false },
    ]);
    expect(now.next).toMatchObject({ slot: 2, key: "B", title: "Session B", activity: "Gym" });
  });

  it("slots are per week: a slot done in week 1 is open in week 2, with the phase of that week", () => {
    const now = programNow(p(), "2026-11-26", (w) => w === 1, fill);
    expect(now.week).toBe(2);
    expect(now.slots.every((s) => !s.done)).toBe(true);
    expect(now.next?.slot).toBe(1);
  });

  it("has no next when every slot is done, when not running, or when paused or done", () => {
    expect(programNow(p(), "2026-11-20", () => true, fill).next).toBeNull();
    expect(programNow(p(), "2026-11-18", none, fill).next).toBeNull();
    expect(programNow(p(), "2026-12-03", none, fill).next).toBeNull();
    expect(programNow(p("paused"), "2026-11-20", none, fill).next).toBeNull();
    expect(programNow(p("done"), "2026-11-20", none, fill).next).toBeNull();
  });

  it("reads the day in APP_TIMEZONE (the edge of midnight)", () => {
    const at = Date.UTC(2026, 10, 19, 23, 30);
    expect(localDate(at)).toBe("2026-11-19");
    vi.stubEnv("APP_TIMEZONE", "Pacific/Auckland");
    expect(localDate(at)).toBe("2026-11-20");
    vi.stubEnv("APP_TIMEZONE", "America/Los_Angeles");
    expect(localDate(Date.UTC(2026, 10, 19, 3))).toBe("2026-11-18");
  });
});

describe("fillKg", () => {
  const done = (name: string, kg: number, extra: Partial<Extract<Exercise, { sets: { kg: number }[] }>> = {}): Exercise => ({ name, sets: [{ reps: 5, kg: kg - 10, max: false }, { reps: 5, kg, max: false }], ...extra });
  const written: PlanExercise[] = [{ name: "Squat", sets: [{ reps: 8, kg: 20, max: false }, { reps: 6, kg: 20, max: true }], note: "slow" }, { name: "Bike", measure: "time", sets: [{ minutes: 30 }] }, ex("Row", 30)];

  it("takes the sets of the program session first, set by set, case and outer space ignored", () => {
    const out = fillKg(written, { exercises: [done(" squat ", 60)] }, [{ exercises: [done("Squat", 99)] }]);
    expect(out[0]).toEqual({ name: "Squat", sets: [{ reps: 8, kg: 50, max: false }, { reps: 6, kg: 60, max: true }], note: "slow" });
  });

  it("falls back to the newest log session that has the exercise, then to the written kg", () => {
    const out = fillKg(written, { exercises: [done("Bench", 50)] }, [{ exercises: [done("Curl", 15)] }, { exercises: [done("Squat", 70)] }, { exercises: [done("Squat", 90)] }]);
    expect(out[0]).toMatchObject({ sets: [{ kg: 60 }, { kg: 70 }] });
    expect(out[2]).toEqual(written[2]); // Row is nowhere: as written
  });

  it("keeps reps, set count, order and time exercises as written", () => {
    const out = fillKg(written, null, [{ exercises: [done("Squat", 70), { name: "Bike", measure: "time", sets: [{ minutes: 5 }] }] }]);
    expect(out.map((e) => e.name)).toEqual(["Squat", "Bike", "Row"]);
    expect(out[0]!.sets).toHaveLength(2);
    expect((out[0]!.sets as { reps: number }[]).map((s) => s.reps)).toEqual([8, 6]);
    expect(out[1]).toEqual(written[1]);
  });

  it("does not change the written session itself", () => {
    const copy = JSON.stringify(written);
    fillKg(written, null, [{ exercises: [done("Squat", 70)] }]);
    expect(JSON.stringify(written)).toBe(copy);
  });
});

describe("proposal policy", () => {
  it("a program always needs an explicit Agree", () => {
    expect(approvalFor("program", "request")).toBe("explicit");
    expect(approvalFor("program", "feedback")).toBe("explicit");
    expect(approvalFor("program", "chat")).toBe("explicit");
  });
});

describe("the short exercise form of build_program", () => {
  it("makes full sets from {sets, reps, kg} and from {sets, minutes}", async () => {
    const { ProgramBuildSchema } = await import("../functions/model/schema");
    const { MOCK_PROGRAM } = await import("../functions/model/ai/providers/mock");
    const short = { ...MOCK_PROGRAM, phases: [{ ...MOCK_PROGRAM.phases[0]!, sessions: [{ key: "A", title: "A", activity: "Gym", exercises: [{ name: "Leg press", sets: 3, reps: 10, kg: 20, note: "slow" }, { name: "Wall sit", sets: 2, minutes: 0.5 }, { name: "Squat", sets: 2, reps: 12 }] }, MOCK_PROGRAM.phases[0]!.sessions[1]!] }] };
    const out = ProgramBuildSchema.parse(short);
    expect(out.phases[0]!.sessions[0]!.exercises).toEqual([
      { name: "Leg press", sets: [{ reps: 10, kg: 20, max: false }, { reps: 10, kg: 20, max: false }, { reps: 10, kg: 20, max: false }], note: "slow" },
      { name: "Wall sit", measure: "time", sets: [{ minutes: 0.5 }, { minutes: 0.5 }] },
      { name: "Squat", sets: [{ reps: 12, kg: 0, max: false }, { reps: 12, kg: 0, max: false }] },
    ]);
    expect(ProgramBuildSchema.parse(MOCK_PROGRAM).phases[0]!.sessions[1]!.exercises[0]).toEqual({ name: "Bike", measure: "time", sets: [{ minutes: 30 }] });
  });
});
