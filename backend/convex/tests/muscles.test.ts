import { describe, expect, it } from "vitest";
import { focusPartsFromGoals } from "../functions/model/rules/focusParts";
import { avoidedInPlan, dropAvoided, limitsLoadedBy, sessionLoadsPart } from "../functions/model/rules/limits";
import { loadForDays } from "../functions/model/rules/load";
import { MUSCLE_KEYS, allMusclesFor, musclesFor } from "../functions/model/rules/muscles";
import type { Limit, Session } from "../functions/model/schema";

const NAMES = ["Back Extension", "Bench Press", "Biceps Curl", "Dips", "Face Pull", "Flat Abs", "Glute Drive", "Hammer Shoulder Press", "Shoulder Press", "Hip Abduction", "Hip Adduction", "Incline Ab Twist", "Lat Pulldown", "Wide-Grip Lat Pulldown", "Iso-Lateral Lat Pulldown", "Leg Extension", "Leg Press", "Low Row", "Single-Arm Low Row", "Prone Leg Curl", "Pull-Up", "Reverse Fly", "Rope Cable Biceps Curl", "Squat", "Hack Squat", "Standing Cable Hip Abduction", "Standing Calf Raise", "Straight Leg Raise", "Superman Raise", "Triceps Rope Pushdown", "Lateral Raise", "Pullover Machine", "Incline Dumbbell Press", "Pec Deck"];

const day = 86_400_000;
const now = Date.UTC(2026, 10, 17);
const gym = (id: string, endedAt: number, ex: [string, number][]): Session => ({
  id, kind: "gym", type: "Gym", focus: "Upper", startedAt: endedAt - 3_600_000, endedAt, source: "app",
  exercises: ex.map(([name, n]) => ({ name, sets: Array.from({ length: n }, () => ({ reps: 8, kg: 10, max: false })) })),
});
const activity = (id: string, type: string, endedAt: number): Session => ({ id, kind: "activity", type, startedAt: endedAt - 1000, endedAt, exercises: [], source: "app" });
const limit = (over: Partial<Limit>): Limit => ({ limitId: "l1", part: "left_knee", title: "Left knee", status: "active", rules: [], ...over });

describe("exercise muscles", () => {
  it("covers every listed name with a primary muscle", () => {
    for (const n of NAMES) expect(musclesFor(n).primary.length, n).toBeGreaterThan(0);
  });
  it("is case and hyphen tolerant", () => {
    expect(musclesFor("wide grip LAT pulldown").primary).toEqual(["lats"]);
    expect(allMusclesFor("Bench press")).toEqual(["chest", "triceps", "shoulders"]);
  });
  it("falls back to keywords and returns nothing for unknown names", () => {
    expect(musclesFor("Cable Hammer Curl").primary).toEqual(["biceps"]);
    expect(musclesFor("Machine Chest Press").primary).toEqual(["chest", "shoulders"]);
    expect(musclesFor("Seated Cable Row").primary).toEqual(["upper_back", "lats"]);
    expect(musclesFor("Walking Lunge").primary).toEqual(["quads", "glutes"]);
    expect(musclesFor("Bulgarian Split Squat").primary).toEqual(["quads", "glutes"]);
    expect(musclesFor("Farmer walk")).toEqual({ primary: [], secondary: [] });
    expect(musclesFor("Arrow shooting").primary).toEqual([]);
  });
});

describe("load levels", () => {
  it("has every muscle key; 0 for nothing", () => {
    const l = loadForDays([], 14, now);
    expect(Object.keys(l).sort()).toEqual([...MUSCLE_KEYS].sort());
    expect(Object.values(l).every((x) => x === 0)).toBe(true);
  });
  it("splits by share of the busiest muscle; secondary counts half; windows apply", () => {
    const s = [gym("a", now - day, [["Bench Press", 10]]), gym("old", now - 30 * day, [["Squat", 10]])];
    const l14 = loadForDays(s, 14, now);
    expect(l14.chest).toBe(3); // 10 sets
    expect(l14.triceps).toBe(2); // 5 sets = 0.5 share
    expect(l14.quads).toBe(0);
    const l90 = loadForDays(s, 90, now);
    expect(l90.quads).toBe(3);
    expect(l90.chest).toBe(3);
    expect(l90.hamstrings).toBe(2); // 5 of 10
    expect(l90.lower_back).toBe(2);
    expect(loadForDays([gym("b", now - day, [["Bench Press", 20], ["Lateral Raise", 1]])], 14, now).shoulders).toBe(2); // 11 of 20 = 0.55
  });
  it("counts run and cycling like sets", () => {
    const l = loadForDays([activity("r", "Run", now - day), activity("c", "Cycling", now - day), activity("s", "Swim", now - day)], 14, now);
    expect(l.quads).toBe(3); // 7
    expect(l.hamstrings).toBe(2); // 4 of 7 = 0.57
    expect(l.calves).toBe(3);
    expect(l.chest).toBe(0);
  });
});

describe("which limits a session loads", () => {
  it("knees: leg work, run, cycling, any activity; not upper work", () => {
    expect(sessionLoadsPart(gym("a", now, [["Leg Press", 3]]), "left_knee")).toBe(true);
    expect(sessionLoadsPart(gym("a", now, [["Bench Press", 3]]), "left_knee")).toBe(false);
    expect(sessionLoadsPart(activity("a", "Yoga", now), "right_knee")).toBe(true);
  });
  it("wrists, shoulders, lower back, ankles, neck", () => {
    expect(sessionLoadsPart(gym("a", now, [["Biceps Curl", 3]]), "wrists")).toBe(true);
    expect(sessionLoadsPart(activity("a", "Bouldering", now), "left_wrist")).toBe(true);
    expect(sessionLoadsPart(activity("a", "Run", now), "left_wrist")).toBe(false);
    expect(sessionLoadsPart(activity("a", "Swim", now), "left_shoulder")).toBe(true);
    expect(sessionLoadsPart(gym("a", now, [["Back Extension", 3]]), "lower_back")).toBe(true);
    expect(sessionLoadsPart(gym("a", now, [["Flat Abs", 3]]), "lower_back")).toBe(false);
    expect(sessionLoadsPart(activity("a", "Run", now), "right_ankle")).toBe(true);
    expect(sessionLoadsPart(activity("a", "Cycling", now), "right_ankle")).toBe(false);
    expect(sessionLoadsPart(gym("a", now, [["Face Pull", 3]]), "neck")).toBe(true);
    expect(sessionLoadsPart(gym("a", now, [["Leg Extension", 3]]), "neck")).toBe(false);
  });
  it("a muscle part is loaded by training that muscle; cleared limits never", () => {
    expect(sessionLoadsPart(gym("a", now, [["Pec Deck", 3]]), "chest")).toBe(true);
    expect(sessionLoadsPart(activity("a", "Run", now), "calves")).toBe(true);
    expect(limitsLoadedBy(activity("a", "Run", now), [limit({}), limit({ limitId: "l2", status: "cleared" })]).map((l) => l.limitId)).toEqual(["l1"]);
  });
});

describe("focus parts", () => {
  it("come from active goals: exercise, then title words, in canonical order", () => {
    const g = (title: string, exercise?: string, status: "active" | "done" = "active") => ({ title, exercise, status });
    expect(focusPartsFromGoals([g("Bench 80 kg", "Bench Press"), g("Stronger calves")])).toEqual(["chest", "calves"]);
    expect(focusPartsFromGoals([g("Squat 100", "Squat")])).toEqual(["glutes", "quads"]);
    expect(focusPartsFromGoals([g("Train 3x a week")])).toEqual([]);
    expect(focusPartsFromGoals([g("Big biceps", undefined, "done")])).toEqual([]);
    expect(focusPartsFromGoals([g("Wider back")])).toEqual(["upper_back", "lats"]);
  });
});

describe("avoid rules", () => {
  const l = limit({ rules: [{ kind: "avoid", text: "No deep squats", exercises: ["Squat", "hack squat"] }, { kind: "light", text: "Easy on press", exercises: ["Leg Press"] }] });
  const plan = (...names: string[]) => ({ rationale: "r", exercises: names.map((name) => ({ name, sets: [] })) });
  it("finds and drops avoided exercises of non-cleared limits only", () => {
    expect(avoidedInPlan(plan("Leg Press", "Hack Squat"), [l])).toBe("Hack Squat");
    expect(avoidedInPlan(plan("Leg Press"), [l])).toBeNull();
    expect(avoidedInPlan(plan("Squat"), [{ ...l, status: "cleared" }])).toBeNull();
    expect(dropAvoided(plan("Squat", "Leg Press"), [l]).exercises.map((e) => e.name)).toEqual(["Leg Press"]);
  });
});
