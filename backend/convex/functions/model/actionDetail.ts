import type { OpenExercise } from "./openSession";
import { formatSets } from "./proposalText";
import { normName } from "./rules/muscles";
import type { PlanExercise } from "./schema";

export const DETAIL_MAX = 120;

/** A detail line cut to the limit. */
export const cut = (s: string): string => (s.length <= DETAIL_MAX ? s : `${s.slice(0, DETAIL_MAX - 1).trimEnd()}…`);

const setsKey = (sets: object[]) => JSON.stringify(sets.map((s) => ({ ...s })));

/** The planned sets of an open exercise, as the plan shape that `formatSets` reads. */
function asPlan(e: OpenExercise): PlanExercise {
  return e.measure === "time"
    ? { name: e.name, measure: "time", sets: e.sets.map((s) => ({ minutes: s.minutes ?? 0, ...(s.distanceKm !== undefined ? { distanceKm: s.distanceKm } : {}) })) }
    : { name: e.name, sets: e.sets.map((s) => ({ reps: s.reps ?? 0, kg: s.kg ?? 0, max: s.max ?? false })) };
}

/** "Tandem Stand → Balance Board", or, for the same name, what changed: "Balance Board: note and sets changed". Pure. */
export function replaceDetail(before: OpenExercise, after: PlanExercise): string {
  if (normName(before.name) !== normName(after.name)) return cut(`${before.name} → ${after.name.trim()}`);
  const note = (before.note ?? "").trim() !== (after.note ?? "").trim();
  const was = asPlan(before);
  const sets = (before.measure === "time") !== (after.measure === "time") || setsKey(was.sets) !== setsKey(after.sets.map((s) => ("max" in s ? { reps: s.reps, kg: s.kg, max: s.max ?? false } : s)));
  const what = note && sets ? "note and sets changed" : note ? "note changed" : sets ? "sets changed" : "nothing changed";
  return cut(`${after.name.trim()}: ${what}`);
}

export const addDetail = (e: PlanExercise): string => cut(`Added: ${e.name.trim()}${formatSets(e) ? `, ${formatSets(e)}` : ""}`);
export const removeDetail = (e: OpenExercise): string => cut(`Removed: ${e.name}`);
export const programDetail = (change: boolean): string => (change ? "Program change: being written" : "New program: being written");
export const proposeDetail = (n: number): string => `Proposed: ${n} exercise${n === 1 ? "" : "s"}`;

/** "Place: Home → Gym", or "Place: Gym" when the session had no place. Pure. */
export const sessionPlaceDetail = (before: string | null, after: string): string => cut(before ? `Place: ${before} → ${after}` : `Place: ${after}`);

/** "Gym: added balance board", "Gym: removed second bike", or both. */
export function placeDetail(place: string, add?: string, remove?: string): string {
  const parts = [...(add?.trim() ? [`added ${add.trim()}`] : []), ...(remove?.trim() ? [`removed ${remove.trim()}`] : [])];
  return cut(`${place}: ${parts.join(", ")}`);
}
