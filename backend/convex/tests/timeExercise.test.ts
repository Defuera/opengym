import { describe, expect, it } from "vitest";
import { coachPicture } from "../functions/model/ai/jobs/coachPicture";
import { logForPrompt } from "../functions/model/ai/jobs/shared";
import { buildSessionJob } from "../functions/model/ai/jobs/buildSession";
import { planSessionJob } from "../functions/model/ai/jobs/planSession";
import { finalizeStartProposal } from "../functions/model/proposals";
import { loadLevels, setsPerMuscle } from "../functions/model/rules/load";
import { musclesFor } from "../functions/model/rules/muscles";
import { fitPlanToMinutes, rulesPlan } from "../functions/model/rules/planner";
import { resolveDashboard } from "../functions/model/rules/dashboard";
import { rulesReview } from "../functions/model/rules/review";
import { stats } from "../functions/model/rules/stats";
import { ExerciseSchema, PlanDraftSchema, PlanExerciseSchema, SessionSchema, type Session } from "../functions/model/schema";
import { setup, TOKEN } from "./helpers";

const base = { id: "s1", kind: "gym" as const, type: "Gym", startedAt: 1000, endedAt: 2000, source: "app" as const };
const bike = { name: "Stationary bike", measure: "time" as const, sets: [{ minutes: 25, distanceKm: 10.9 }] };
const bench = { name: "Bench press", sets: [{ reps: 6, kg: 60, max: false }] };
const session = (id: string, endedAt: number, exercises: Session["exercises"]): Session => ({ ...base, id, startedAt: endedAt - 1000, endedAt, exercises });

describe("time exercise shape", () => {
  it("accepts both measures", () => {
    expect(ExerciseSchema.safeParse(bench).success).toBe(true);
    expect(ExerciseSchema.safeParse({ ...bench, measure: "sets" }).success).toBe(true);
    expect(ExerciseSchema.safeParse(bike).success).toBe(true);
    expect(SessionSchema.safeParse({ ...base, exercises: [bench, bike] }).success).toBe(true);
    expect(ExerciseSchema.safeParse({ name: "Plank", measure: "time", sets: [{ minutes: 1 }, { minutes: 2, note: "slow" }] }).success).toBe(true);
  });

  it("rejects mixed shapes and bad minutes", () => {
    expect(ExerciseSchema.safeParse({ name: "Bike", measure: "time", sets: [{ reps: 8, kg: 0, max: false }] }).success).toBe(false);
    expect(ExerciseSchema.safeParse({ name: "Bike", measure: "time", sets: [{ minutes: 5, reps: 8, kg: 0, max: false }] }).success).toBe(false);
    expect(ExerciseSchema.safeParse({ name: "Bench", sets: [{ minutes: 5 }] }).success).toBe(false);
    expect(ExerciseSchema.safeParse({ name: "Bench", measure: "sets", sets: [{ reps: 5, kg: 10, max: false, minutes: 5 }] }).success).toBe(false);
    for (const minutes of [0, -1, 601]) expect(ExerciseSchema.safeParse({ name: "Bike", measure: "time", sets: [{ minutes }] }).success).toBe(false);
    expect(ExerciseSchema.safeParse({ name: "Bike", measure: "other", sets: [{ minutes: 5 }] }).success).toBe(false);
  });

  it("old rows without measure still parse", () => {
    const old = { ...base, exercises: [{ name: "Squat", sets: [{ reps: 5, kg: 100, max: false, failed: true, at: 5 }] }] };
    const r = SessionSchema.safeParse(old);
    expect(r.success).toBe(true);
  });

  it("plan drafts take both measures", () => {
    const draft = { rationale: "x", exercises: [{ name: "Squat", sets: [{ reps: 5, kg: 100 }] }, { name: "Bike", measure: "time", sets: [{ minutes: 20 }] }] };
    expect(PlanDraftSchema.safeParse(draft).success).toBe(true);
    expect(PlanExerciseSchema.safeParse({ name: "Bike", measure: "time", sets: [{ reps: 5, kg: 1 }] }).success).toBe(false);
  });

  it("the convex command stores a time exercise and rejects a mixed one", async () => {
    const t = setup();
    const s = { sessionId: "t1", kind: "gym" as const, type: "Gym", startedAt: 1000, endedAt: 2000, source: "app" as const };
    await t.mutation("commands/sessions:save" as never, { token: TOKEN, session: { ...s, exercises: [bike] } } as never);
    await expect(t.mutation("commands/sessions:save" as never, { token: TOKEN, session: { ...s, sessionId: "t2", exercises: [{ ...bike, sets: [{ reps: 8, kg: 0, max: false }] }] } } as never)).rejects.toThrow();
    await t.mutation("commands/sessions:save" as never, { token: TOKEN, session: { ...s, sessionId: "t3", exercises: [bench] } } as never);
  });
});

describe("time exercise in rules", () => {
  it("rulesPlan copies the last time entry", () => {
    const log = [session("a", 10_000, [bench, { ...bike, sets: [{ minutes: 20 }] }]), session("b", 20_000, [bench, bike])];
    const plan = rulesPlan(log, "Gym");
    const b = plan.exercises.find((e) => e.name === "Stationary bike")!;
    expect(b.measure).toBe("time");
    expect(b.sets).toEqual([{ minutes: 25, distanceKm: 10.9 }]);
    expect(plan.exercises.find((e) => e.name === "Bench press")!.sets).toEqual([{ reps: 6, kg: 60, max: false }]);
    expect(PlanDraftSchema.safeParse(plan).success).toBe(true);
  });

  it("finalize keeps a time exercise and fits it to the time asked", () => {
    const draft = { rationale: "r", exercises: [{ name: "Squat", sets: [{ reps: 5, kg: 50, max: false }, { reps: 5, kg: 50, max: false }] }, { name: "Stationary bike", measure: "time" as const, sets: [{ minutes: 60 }] }] };
    const kept = finalizeStartProposal({ kind: "gym", type: "Gym", plan: draft }, []);
    expect(kept.plan!.exercises[1]).toEqual({ name: "Stationary bike", measure: "time", sets: [{ minutes: 60 }] });
    // 30 minutes = 30 budget: 2 sets cost 4, the bike is cut to 26
    const fitted = finalizeStartProposal({ kind: "gym", type: "Gym", minutes: 30, plan: draft }, []);
    expect(fitted.plan!.exercises[0]!.sets).toHaveLength(2);
    expect(fitted.plan!.exercises[1]).toEqual({ name: "Stationary bike", measure: "time", sets: [{ minutes: 26 }] });
    // short time: the time entry goes first and takes the whole budget
    const bikeFirst = fitPlanToMinutes({ rationale: "r", exercises: [draft.exercises[1]!, draft.exercises[0]!] }, 10);
    expect(bikeFirst.exercises).toHaveLength(1);
    expect(bikeFirst.exercises[0]!.sets).toEqual([{ minutes: 10 }]);
  });

  it("a hold shorter than one minute stays when it fits", () => {
    const holds = { name: "Wall Sit", measure: "time" as const, sets: [{ minutes: 0.5 }, { minutes: 0.5 }, { minutes: 0.5 }] };
    const fitted = fitPlanToMinutes({ rationale: "r", exercises: [{ name: "Leg Press", sets: [{ reps: 10, kg: 50, max: false }] }, holds] }, 20);
    expect(fitted.exercises[1]).toEqual(holds);
  });

  it("load counts minutes: one set per 4 minutes", () => {
    const l = setsPerMuscle([session("a", 5000, [{ name: "Stationary bike", measure: "time", sets: [{ minutes: 20 }] }])], 0, 10_000);
    expect(l.quads).toBe(5);
    expect(l.glutes).toBe(2.5);
    expect(loadLevels(l).quads).toBe(3);
    expect(musclesFor("Treadmill").primary).toContain("calves");
    expect(musclesFor("Rowing machine").primary).toContain("lats");
    expect(musclesFor("Cycling").primary).toContain("quads");
  });

  it("best weight, stats and dashboard ignore time entries", () => {
    const log = [session("a", 5000, [bike, bench])];
    const st = stats(log, 7, 6000);
    expect(st.sets).toBe(1);
    expect(st.best).toBe("Bench press");
    const bikeOnly = [session("a", 5000, [bike])];
    expect(stats(bikeOnly, 7, 6000).best).toBeNull();
    const d = resolveDashboard({ source: "rules", modules: [{ type: "trend", exercise: "Stationary bike" }, { type: "recent_sessions", limit: 3 }] }, bikeOnly, [], 7, 6000);
    expect(JSON.stringify(d)).toContain("25 min");
    // No weight was lifted: there is no top set to draw.
    expect(d.modules.some((m) => m.type === "trend")).toBe(false);
  });

  it("review counts timed exercises, not their entries as sets", () => {
    const r = rulesReview([session("a", 5000, [bike, bench])], session("a", 5000, [bike, bench]));
    expect(r.summary).toContain("1 sets");
    expect(r.summary).toContain("1 timed");
  });
});

describe("time exercise in prompts", () => {
  it("logForPrompt and coachPicture print minutes", () => {
    const log = [session("a", 86_400_000 * 3, [bike, bench])];
    const lp = logForPrompt(log);
    expect(lp[0]!.exercises[0]!.sets).toBe("25 min, 10.9 km");
    expect(lp[0]!.exercises[1]!.sets).toBe("6x60");
    expect(logForPrompt([session("b", 5000, [{ name: "Plank", measure: "time", sets: [{ minutes: 25 }] }])])[0]!.exercises[0]!.sets).toBe("25 min");
    const pic = coachPicture(log, [], [], [], [], 86_400_000 * 4);
    const row = pic.exercisesTheUserKnows.find((e) => e.name === "Stationary bike")!;
    expect(row.lastSets).toBe("25 min, 10.9 km");
    expect(row).toMatchObject({ measure: "time", bestKg: 0 });
    expect(pic.exercisesTheUserKnows.find((e) => e.name === "Bench press")).not.toHaveProperty("measure");
    expect(pic.recentSessions[0]!.exercises[0]).toBe("Stationary bike: 25 min, 10.9 km");
  });

  it("the AI prompts name the time shape", () => {
    const plan = planSessionJob.build({ activity: "Gym", sessions: [], goals: [], context: [], limits: [], rules: { rationale: "", exercises: [] } } as never);
    expect(plan.system).toContain('"measure": "time"');
    expect(plan.system).toContain("use measure time with minutes, not reps");
    expect(buildSessionJob.build({ name: null, note: "", request: "bike", picture: coachPicture([], [], [], [], [], 0), limits: [] } as never).system).toContain("use measure time with minutes, not reps");
    expect(buildSessionJob.build({ name: null, note: "", request: "bike", picture: coachPicture([], [], [], [], [], 0), limits: [] } as never).system).toContain('"measure": "time"');
  });
});
