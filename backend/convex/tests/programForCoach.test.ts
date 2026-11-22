import { describe, expect, it } from "vitest";
import { buildSessionJob } from "../functions/model/ai/jobs/buildSession";
import { type ProgramForCoach, programLinkFor, programsForCoach } from "../functions/model/programForCoach";
import { StartProposalSchema } from "../functions/model/schema";
import type { Session } from "../functions/model/schema";
import { buildStartInput } from "../functions/model/startInput";

const program: ProgramForCoach = {
  programId: "p1",
  title: "Knee prep",
  purpose: "Ski on 19 December",
  status: "active",
  startsOn: "2026-11-19",
  endsOn: "2026-12-02",
  week: ["A", "C", "A"],
  phases: [{
    title: "Start", weekFrom: 1, weekTo: 2, note: "Keep loads light.",
    sessions: [
      { key: "A", title: "Gym legs", activity: "Gym", exercises: [{ name: "Leg Press", sets: [{ reps: 10, kg: 20, max: false }, { reps: 10, kg: 20, max: false }], note: "to 60 degrees" }] },
      { key: "C", title: "Bike day", activity: "Cycling", exercises: [{ name: "Stationary Bike", measure: "time", sets: [{ minutes: 30 }] }] },
    ],
  }],
  rules: ["Stop at pain above 3 of 10."],
  tests: [{ text: "Wall sit 60 s" }],
};
const done = (slot: number): Session => ({ id: `s${slot}`, kind: "gym", type: "Gym", startedAt: Date.UTC(2026, 10, 20, 9), endedAt: Date.UTC(2026, 10, 20, 10), exercises: [], source: "app", programId: "p1", programWeek: 1, programSlot: slot, programKey: "A" });

describe("the program as the coach reads it (ADR-030)", () => {
  it("gives the week, the phase, the slots with done or not, and the sessions as written", () => {
    const [p] = programsForCoach([program], [done(1)], "2026-11-23");
    expect(p).toMatchObject({ programId: "p1", week: "1 of 2", phase: { title: "Start", note: "Keep loads light." }, rules: ["Stop at pain above 3 of 10."], tests: ["Wall sit 60 s"] });
    expect(p!.slotsThisWeek).toEqual([{ slot: 1, key: "A", title: "Gym legs", done: true }, { slot: 2, key: "C", title: "Bike day", done: false }, { slot: 3, key: "A", title: "Gym legs", done: false }]);
    expect(p!.sessionsAsWritten[0]).toEqual({ key: "A", title: "Gym legs", activity: "Gym", exercises: ["Leg Press: 10x20, 10x20 (to 60 degrees)"] });
    expect(p!.sessionsAsWritten[1]!.exercises).toEqual(["Stationary Bike: 30 min"]);
  });

  it("leaves out a paused program, one that has not started and one that ended", () => {
    expect(programsForCoach([{ ...program, status: "paused" }], [], "2026-11-23")).toEqual([]);
    expect(programsForCoach([program], [], "2026-11-18")).toEqual([]);
    expect(programsForCoach([program], [], "2026-12-03")).toEqual([]);
  });

  it("goes into the build_session prompt only when a program runs", () => {
    const data = { sessions: [], goals: [], context: [], limits: [], places: [], entries: [], now: Date.UTC(2026, 10, 23, 9) };
    const prompt = (programs?: ProgramForCoach[]) => buildSessionJob.build(buildStartInput({ name: "Gym" }, { ...data, ...(programs ? { programs } : {}) }).job).messages[0]!.content;
    expect(JSON.parse(prompt([program]).split("INPUT_JSON:\n")[1]!).programsThePersonFollows[0].title).toBe("Knee prep");
    expect(prompt()).not.toContain("programsThePersonFollows");
    expect(prompt([{ ...program, status: "done" }])).not.toContain("programsThePersonFollows");
  });
});

describe("the program link of a proposed session", () => {
  it("is the first open slot of this week with the key the coach named", () => {
    expect(programLinkFor(program, "A", [], "2026-11-23")).toEqual({ programId: "p1", week: 1, slot: 1, key: "A" });
    expect(programLinkFor(program, "A", [done(1)], "2026-11-23")).toEqual({ programId: "p1", week: 1, slot: 3, key: "A" });
    // A new program week starts with every slot open again.
    expect(programLinkFor(program, "A", [done(1), done(3)], "2026-11-27")).toEqual({ programId: "p1", week: 2, slot: 1, key: "A" });
  });

  it("is none when every slot with the key is done, the key is unknown, or the program does not run", () => {
    expect(programLinkFor(program, "A", [done(1), done(3)], "2026-11-23")).toBeNull();
    expect(programLinkFor(program, "Z", [], "2026-11-23")).toBeNull();
    expect(programLinkFor({ ...program, status: "paused" }, "A", [], "2026-11-23")).toBeNull();
    expect(programLinkFor(program, "A", [], "2026-12-03")).toBeNull();
    expect(programLinkFor(null, "A", [], "2026-11-23")).toBeNull();
  });

  it("a proposal keeps a well-formed program and drops a broken one without failing", () => {
    const base = { kind: "gym", type: "Gym", plan: { rationale: "r", exercises: [{ name: "Leg Press", sets: [{ reps: 10, kg: 20, max: false }] }] } };
    expect(StartProposalSchema.parse({ ...base, program: { programId: "p1", key: "A" } }).program).toEqual({ programId: "p1", key: "A" });
    expect(StartProposalSchema.parse({ ...base, program: null }).program).toBeUndefined();
    expect(StartProposalSchema.parse({ ...base, program: { programId: "p1" } }).program).toBeUndefined();
  });
});
