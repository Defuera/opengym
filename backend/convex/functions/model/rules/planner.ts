import type { PlanDraft, PlanExercise, PlanSet, Session } from "../schema";
import { lastOfActivity } from "./foci";
import { fmtKg, truncate } from "./util";

export const MAX_PLAN_EXERCISES = 12;
export const MAX_PLAN_SETS = 10;
export const WEIGHT_CAP_FACTOR = 1.25;

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

/** Sets for an exercise with no sets in the log: three open sets of 8 reps, no weight. No exercise has special numbers. */
export function defaultSets(): PlanSet[] {
  return [0, 1, 2].map(() => ({ reps: 8, kg: 0, max: false }));
}

/**
 * Rules plan for a session with sets: repeat the user's own last session of that activity (and focus, when one is given),
 * with the last sets logged for each exercise. With no such session the plan is EMPTY: no starter template (ADR-016).
 */
export function rulesPlan(sessions: Session[], activity: string, focus?: string): PlanDraft {
  const last = lastOfActivity(sessions, activity, focus);
  const label = focus ? `${activity} ${focus}` : activity;
  if (!last || last.exercises.length === 0) return { rationale: truncate(`No ${label} session logged yet. Start empty and add what you do.`, 200), exercises: [] };
  const exercises: PlanExercise[] = last.exercises.map((e) => ({ name: e.name, sets: lastSetsFor(sessions, e.name) ?? defaultSets() }));
  return { rationale: truncate(`Repeats your last ${label} session with the same sets.`, 200), exercises };
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

/** About this many minutes per set, rest included. Used to keep a plan within the time the user asked for. */
export const MINUTES_PER_SET = 2;
export const MIN_FIT_SETS = 4;

/** Keeps a plan to the time asked for: at most max(4, minutes / 2) sets in total, cut from the end; an exercise left with no sets is dropped. */
export function fitPlanToMinutes(draft: PlanDraft, minutes: number): PlanDraft {
  let left = Math.max(MIN_FIT_SETS, Math.ceil(minutes / MINUTES_PER_SET));
  const exercises: PlanExercise[] = [];
  for (const e of draft.exercises) {
    if (left <= 0) break;
    const sets = e.sets.slice(0, left);
    left -= sets.length;
    if (sets.length > 0) exercises.push({ ...e, sets });
  }
  return { ...draft, exercises };
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
