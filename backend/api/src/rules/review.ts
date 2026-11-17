import type { Review, Session } from "../schema";
import { fmtKg, truncate } from "./util";

type Draft = Pick<Review, "summary" | "changes">;

function topByExercise(s: Session): Map<string, number> {
  const m = new Map<string, number>();
  for (const e of s.exercises) for (const x of e.sets) m.set(e.name, Math.max(m.get(e.name) ?? 0, x.kg));
  return m;
}

export function previousOfType(sessions: Session[], s: Session): Session | null {
  const prev = sessions.filter((x) => x.id !== s.id && x.kind === s.kind && x.type === s.type && x.endedAt <= s.endedAt);
  return prev.length ? prev[prev.length - 1]! : null;
}

/** Set counts and top sets vs the previous session of that type. */
export function rulesReview(sessions: Session[], s: Session): Draft {
  const prev = previousOfType(sessions, s);
  if (s.kind === "activity") {
    const bits = [s.minutes !== undefined ? `${s.minutes} min` : null, s.distanceKm !== undefined ? `${fmtKg(s.distanceKm)} km` : null].filter(Boolean);
    const changes: string[] = [];
    if (prev && s.minutes !== undefined && prev.minutes !== undefined) changes.push(`Duration ${s.minutes} min (was ${prev.minutes})`);
    if (prev && s.distanceKm !== undefined && prev.distanceKm !== undefined) changes.push(`Distance ${fmtKg(s.distanceKm)} km (was ${fmtKg(prev.distanceKm)})`);
    return { summary: `${s.type} logged${bits.length ? `: ${bits.join(", ")}` : ""}.`, changes: changes.slice(0, 5) };
  }
  const sets = s.exercises.reduce((n, e) => n + e.sets.length, 0);
  const summary = `${s.type}: ${s.exercises.length} exercises, ${sets} sets.${prev ? "" : " First session of this type."}`;
  const changes: string[] = [];
  if (prev) {
    const prevSets = prev.exercises.reduce((n, e) => n + e.sets.length, 0);
    if (prevSets !== sets) changes.push(`Total sets ${sets} (was ${prevSets})`);
    const before = topByExercise(prev);
    for (const [name, kg] of topByExercise(s)) {
      const was = before.get(name);
      if (was !== undefined && was !== kg) changes.push(`${name}: top set ${fmtKg(kg)} kg (was ${fmtKg(was)} kg)`);
    }
  }
  return { summary: truncate(summary, 400), changes: changes.slice(0, 5) };
}
