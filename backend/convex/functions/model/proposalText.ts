import type { PlanExercise } from "./schema";

/** The whole-session plan the coach proposes, as stored on the assistant message (ADR-032). */
export interface StoredProposal {
  title?: string;
  exercises: PlanExercise[];
  focus?: string;
  planNote?: string;
  /** The rev of the open session the coach read. */
  rev: number;
  openSessionId: string;
  appliedAt?: number;
}

/** A proposal as the app receives it. `sets` is a short text. */
export interface ProposalView {
  title?: string;
  exercises: { name: string; sets: string }[];
  state: "open" | "applied" | "stale";
}

const num = (n: number) => String(Math.round(n * 100) / 100);

/** One time set: "30 s" under a minute, else "10 min". */
function timeText(minutes: number): string {
  return minutes < 1 ? `${Math.round(minutes * 60)} s` : `${num(minutes)} min`;
}

/**
 * The sets of one exercise as a short text: "3 × 10", "3 × max", "10, 8, 6" (reps differ), "3 × 30 s", "10 min", "2 min, 1 min". Pure.
 * When every set has the same non-zero weight, it follows: "3 × 10 · 40 kg". Otherwise the weight is left out. An exercise with no set gives "".
 */
export function formatSets(e: PlanExercise): string {
  const base = formatBase(e);
  const kg = e.measure === "time" ? undefined : sharedKg(e.sets);
  return base && kg ? `${base} · ${num(kg)} kg` : base;
}

/** The one non-zero weight all sets share, or undefined. */
function sharedKg(sets: { kg: number }[]): number | undefined {
  const first = sets[0]?.kg;
  return first && first > 0 && sets.every((s) => s.kg === first) ? first : undefined;
}

function formatBase(e: PlanExercise): string {
  const parts = e.measure === "time" ? e.sets.map((s) => timeText(s.minutes)) : e.sets.map((s) => (s.max ? "max" : String(s.reps)));
  if (parts.length === 0) return "";
  if (parts.every((p) => p === parts[0])) return parts.length === 1 && e.measure === "time" ? parts[0]! : `${parts.length} × ${parts[0]}`;
  return parts.join(", ");
}

/** The proposal for the app. `state` is worked out by the caller (list query). */
export function proposalView(p: StoredProposal, state: ProposalView["state"]): ProposalView {
  return { ...(p.title ? { title: p.title } : {}), exercises: p.exercises.map((e) => ({ name: e.name, sets: formatSets(e) })), state };
}
