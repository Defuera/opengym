import type { ContextItem, Exercise, Goal, Session } from "../../functions/model/schema";

/** The fixed "now" of every case: Wednesday 2026-11-18, 09:00 UTC. The runner uses it as the clock of the server code. */
export const NOW = Date.UTC(2026, 10, 18, 9, 0, 0);

/** A moment `daysAgo` days before today at `hour` (UTC). */
export const at = (daysAgo: number, hour = 18): number => Date.UTC(2026, 10, 18 - daysAgo, hour, 0, 0);

/** An exercise with sets: pairs of [reps, kg]. */
export const ex = (name: string, ...sets: [number, number][]): Exercise => ({ name, sets: sets.map(([reps, kg]) => ({ reps, kg, max: false })) });

/** An exercise measured in time. */
export const timeEx = (name: string, minutes: number): Exercise => ({ name, measure: "time", sets: [{ minutes }] });

/** A session with sets (kind gym). `type` is the activity name. Lasts `minutes`. */
export function gym(id: string, daysAgo: number, type: string, focus: string | undefined, placeId: string, minutes: number, exercises: Exercise[]): Session {
  const endedAt = at(daysAgo);
  return { id, kind: "gym", type, ...(focus ? { focus } : {}), startedAt: endedAt - minutes * 60_000, endedAt, exercises, minutes, source: "app", placeId };
}

/** A time or distance activity (kind activity): no exercises. */
export function activity(id: string, daysAgo: number, type: string, minutes: number, distanceKm?: number, focus?: string): Session {
  const endedAt = at(daysAgo, 7);
  return { id, kind: "activity", type, ...(focus ? { focus } : {}), startedAt: endedAt - minutes * 60_000, endedAt, exercises: [], minutes, ...(distanceKm !== undefined ? { distanceKm } : {}), source: "app" };
}

export const goal = (id: string, createdDaysAgo: number, g: Pick<Goal, "title" | "kind"> & Partial<Goal>): Goal => ({ id, status: "active", source: "user", createdAt: at(createdDaysAgo, 8), ...g });

export const note = (id: string, createdDaysAgo: number, topic: string, text: string): ContextItem => ({ id, topic, text, active: true, source: "user", createdAt: at(createdDaysAgo, 8) });
