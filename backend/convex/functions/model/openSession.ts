/**
 * The open session (ADR-028): the session the person is doing now, before it is finished. The shape is the app's own (its local
 * storage shape), so the phone and the server hold the same thing. A set with `done: true` is a fact: only the app writes it.
 */
export interface OpenSet {
  reps?: number;
  kg?: number;
  max?: boolean;
  failed?: boolean;
  minutes?: number;
  distanceKm?: number;
  done: boolean;
  at?: number;
}

export interface OpenExercise {
  id: string;
  name: string;
  measure?: "time";
  sets: OpenSet[];
  fresh?: boolean;
  carry?: boolean;
  note?: string;
}

/** A planned exercise as an outside writer gives it: no id, no done flag. */
export interface PlannedExercise {
  name: string;
  measure?: "time";
  note?: string;
  sets: { reps?: number; kg?: number; max?: boolean; minutes?: number; distanceKm?: number }[];
}

export const OPEN_SESSION_MAX_EXERCISES = 40;
export const OPEN_SESSION_MAX_SETS = 30;

const key = (name: string) => name.trim().toLowerCase().replace(/\s+/g, " ");
const hasDone = (e: OpenExercise) => e.sets.some((s) => s.done);

/**
 * The exercises after an outside writer (the coach, the owner's tool) gives a new plan. Plain code keeps the facts:
 * an exercise with a done set stays exactly as it is, in its place at the front; every other exercise is replaced by the plan.
 * A planned exercise with the name of a kept one is left out. `newId` makes the ids of the new exercises.
 */
export function mergePlan(current: OpenExercise[], planned: PlannedExercise[], newId: () => string): OpenExercise[] {
  const kept = current.filter(hasDone);
  const names = new Set(kept.map((e) => key(e.name)));
  const fresh: OpenExercise[] = [];
  for (const p of planned) {
    const k = key(p.name);
    if (!k || names.has(k) || p.sets.length === 0) continue;
    names.add(k);
    const time = p.measure === "time";
    fresh.push({
      id: newId(),
      name: p.name.trim(),
      ...(time ? { measure: "time" as const } : {}),
      sets: p.sets.slice(0, OPEN_SESSION_MAX_SETS).map((s) =>
        time
          ? { minutes: s.minutes ?? 10, ...(s.distanceKm !== undefined ? { distanceKm: s.distanceKm } : {}), done: false }
          : { reps: s.reps ?? 0, kg: s.kg ?? 0, max: s.max ?? false, done: false },
      ),
      fresh: false,
      carry: false,
      ...(p.note ? { note: p.note } : {}),
    });
  }
  return [...kept, ...fresh].slice(0, OPEN_SESSION_MAX_EXERCISES);
}
