import type { PlanDraft, PlanExercise, PlanSet, Session } from "../schema";
import { fmtKg } from "./util";

export const starterTemplates: Record<string, string[]> = {
  Push: ["Bench press", "Overhead press", "Dips", "Triceps pushdown"],
  Pull: ["Pull-up", "Barbell row", "Lat pulldown", "Biceps curl"],
  Legs: ["Squat", "Romanian deadlift", "Leg press", "Calf raise"],
};

export const starterTypes = ["Push", "Pull", "Legs"];

export const MAX_PLAN_EXERCISES = 12;
export const MAX_PLAN_SETS = 10;
export const WEIGHT_CAP_FACTOR = 1.25;

const gym = (sessions: Session[]) => sessions.filter((s) => s.kind === "gym");

/** Sets of the most recent session containing this exercise (case-insensitive). */
export function lastSetsFor(sessions: Session[], name: string): PlanSet[] | null {
  const key = name.toLowerCase();
  for (let i = sessions.length - 1; i >= 0; i--) {
    const s = sessions[i]!;
    if (s.kind !== "gym") continue;
    const e = s.exercises.find((x) => x.name.toLowerCase() === key && x.sets.length > 0);
    if (e) return e.sets.map((x) => ({ reps: x.reps, kg: x.kg, max: x.max }));
  }
  return null;
}

export function defaultSets(name: string): PlanSet[] {
  if (name === "Bench press") {
    return [
      { reps: 6, kg: 20, max: false },
      { reps: 6, kg: 40, max: false },
      { reps: 6, kg: 60, max: false },
      { reps: 1, kg: 60, max: true },
    ];
  }
  return [0, 1, 2].map(() => ({ reps: 8, kg: 0, max: false }));
}

/** Rules plan: repeat the last session of that type, else the starter template. */
export function rulesPlan(sessions: Session[], type: string): PlanDraft {
  const g = gym(sessions);
  let names: string[] | null = null;
  for (let i = g.length - 1; i >= 0; i--) {
    if (g[i]!.type === type) {
      names = g[i]!.exercises.map((e) => e.name);
      break;
    }
  }
  const repeated = names !== null && names.length > 0;
  const use = repeated ? names! : (starterTemplates[type] ?? []);
  const exercises: PlanExercise[] = use.map((name) => ({
    name,
    sets: lastSetsFor(sessions, name) ?? defaultSets(name),
  }));
  const rationale = repeated
    ? `Repeats your last ${type} session with the same sets.`
    : `Starter ${type} template, no ${type} history yet.`;
  return { rationale, exercises };
}

/** Heaviest logged kg per exercise name (lowercase). */
export function heaviestByExercise(sessions: Session[]): Map<string, number> {
  const m = new Map<string, number>();
  for (const s of sessions) {
    for (const e of s.exercises) {
      for (const x of e.sets) {
        const k = e.name.toLowerCase();
        m.set(k, Math.max(m.get(k) ?? 0, x.kg));
      }
    }
  }
  return m;
}

/** Safety limits applied in code after validation. */
export function applyPlanLimits(draft: PlanDraft, sessions: Session[]): PlanDraft {
  const heaviest = heaviestByExercise(sessions);
  const exercises = draft.exercises.slice(0, MAX_PLAN_EXERCISES).map((e) => {
    const top = heaviest.get(e.name.toLowerCase());
    const cap = top !== undefined && top > 0 ? Math.round(top * WEIGHT_CAP_FACTOR * 100) / 100 : null;
    return {
      ...e,
      sets: e.sets.slice(0, MAX_PLAN_SETS).map((s) => ({ ...s, kg: cap !== null ? Math.min(s.kg, cap) : s.kg })),
    };
  });
  return { ...draft, exercises };
}

export function describePlanForPrompt(sessions: Session[], exerciseName: string): string {
  const s = lastSetsFor(sessions, exerciseName);
  return s ? s.map((x) => `${x.reps}x${fmtKg(x.kg)}`).join(", ") : "no history";
}
