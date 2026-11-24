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
  /** The plan note of the coach. */
  note?: string;
  /** What the person wrote about the exercise (ADR-029). */
  comment?: string;
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
/** The person's own work on an exercise: a done set or a comment. An outside writer never touches it. */
export const hasDone = (e: OpenExercise) => e.sets.some((s) => s.done) || !!e.comment;

/** A planned exercise in the open shape: no set done, sets cut to the cap. */
export function toOpenExercise(p: PlannedExercise, id: string): OpenExercise {
  const time = p.measure === "time";
  return {
    id,
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
  };
}

/**
 * The exercises after an outside writer (the coach, the owner's tool) gives a new plan. Plain code keeps the facts:
 * an exercise with a done set or a comment of the person stays exactly as it is, in its place at the front; every other exercise is replaced by the plan.
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
    fresh.push(toOpenExercise(p, newId()));
  }
  return [...kept, ...fresh].slice(0, OPEN_SESSION_MAX_EXERCISES);
}

/** The result of a change of one exercise (ADR-032): the new list, or the reason it was refused. Nothing else changes. */
export type OneChange = { ok: true; exercises: OpenExercise[] } | { ok: false; reason: string };

const LOCKED = "the person has done a set of it or commented on it";

/** Why a planned exercise cannot go into the list (a name already there, no set), or null. `skipId` is the exercise it replaces. */
function plannedProblem(current: OpenExercise[], p: PlannedExercise, skipId?: string): string | null {
  if (!key(p.name)) return "the exercise has no name";
  if (p.sets.length === 0) return "the exercise has no set";
  if (current.some((e) => e.id !== skipId && key(e.name) === key(p.name))) return `"${p.name.trim()}" is in the session already`;
  return null;
}

/** Replaces ONE exercise, in its place, with a planned one. Every other exercise stays byte for byte. The person's work is never replaced. */
export function replaceOne(current: OpenExercise[], exerciseId: string, p: PlannedExercise, id: string): OneChange {
  const i = current.findIndex((e) => e.id === exerciseId);
  if (i < 0) return { ok: false, reason: "no such exercise in the open session" };
  if (hasDone(current[i]!)) return { ok: false, reason: LOCKED };
  const problem = plannedProblem(current, p, exerciseId);
  if (problem) return { ok: false, reason: problem };
  const exercises = current.slice();
  exercises[i] = toOpenExercise(p, id);
  return { ok: true, exercises };
}

/** Adds ONE exercise after `afterId` (or at the end). */
export function addOne(current: OpenExercise[], p: PlannedExercise, id: string, afterId?: string): OneChange {
  if (current.length >= OPEN_SESSION_MAX_EXERCISES) return { ok: false, reason: `the session has ${OPEN_SESSION_MAX_EXERCISES} exercises already` };
  const problem = plannedProblem(current, p);
  if (problem) return { ok: false, reason: problem };
  const at = afterId === undefined ? current.length : current.findIndex((e) => e.id === afterId) + 1;
  if (at === 0) return { ok: false, reason: "no such exercise to add after" };
  return { ok: true, exercises: [...current.slice(0, at), toOpenExercise(p, id), ...current.slice(at)] };
}

/** Removes ONE exercise. The person's work is never removed. */
export function removeOne(current: OpenExercise[], exerciseId: string): OneChange {
  const e = current.find((x) => x.id === exerciseId);
  if (!e) return { ok: false, reason: "no such exercise in the open session" };
  if (hasDone(e)) return { ok: false, reason: LOCKED };
  return { ok: true, exercises: current.filter((x) => x.id !== exerciseId) };
}

/** The fields an outside writer's whole new plan sets (jobs/openSession:replacePlan and the coach's rebuild). Focus cut to 40, the note to 400. */
export function rebuiltPlan(current: OpenExercise[], planned: PlannedExercise[], newId: () => string, focus?: string, planNote?: string) {
  return {
    exercises: mergePlan(current, planned, newId),
    ...(focus !== undefined ? { focus: focus.trim().slice(0, 40) } : {}),
    ...(planNote !== undefined ? { planNote: planNote.slice(0, 400) } : {}),
  };
}
