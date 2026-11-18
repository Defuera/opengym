import { repEntries, totalMinutes, type Session } from "../schema";
import { MUSCLE_KEYS, type MuscleKey, musclesFor } from "./muscles";
import { DAY_MS } from "./util";

export type LoadLevel = 0 | 1 | 2 | 3;
export type LoadMap = Record<MuscleKey, LoadLevel>;

/** Activities count like a number of sets on each muscle they use. */
const ACTIVITY_SETS: Record<string, { sets: number; muscles: MuscleKey[] }> = {
  run: { sets: 4, muscles: ["quads", "hamstrings", "calves", "glutes"] },
  cycling: { sets: 3, muscles: ["quads", "calves"] },
};

const SECONDARY_WEIGHT = 0.5;
/** A time exercise loads its muscles by minutes: about one set per 4 minutes. */
export const MINUTES_PER_LOAD_SET = 4;

/** Weighted sets per muscle for the sessions that ended in [from, to]. */
export function setsPerMuscle(sessions: Session[], from: number, to: number): Record<MuscleKey, number> {
  const out = Object.fromEntries(MUSCLE_KEYS.map((k) => [k, 0])) as Record<MuscleKey, number>;
  for (const s of sessions) {
    if (s.endedAt < from || s.endedAt > to) continue;
    if (s.kind === "gym") {
      for (const e of s.exercises) {
        const x = musclesFor(e.name);
        const n = repEntries(e).length + totalMinutes(e) / MINUTES_PER_LOAD_SET;
        for (const k of x.primary) out[k] += n;
        for (const k of x.secondary) out[k] += n * SECONDARY_WEIGHT;
      }
    } else {
      const a = ACTIVITY_SETS[s.type.toLowerCase()];
      if (a) for (const k of a.muscles) out[k] += a.sets;
    }
  }
  return out;
}

/** 0 = nothing. Otherwise by share of the busiest muscle: >= 0.6 is 3, >= 0.25 is 2, above 0 is 1. */
export function loadLevels(sets: Record<MuscleKey, number>): LoadMap {
  const max = Math.max(0, ...MUSCLE_KEYS.map((k) => sets[k]));
  return Object.fromEntries(
    MUSCLE_KEYS.map((k) => {
      const share = max > 0 ? sets[k] / max : 0;
      return [k, sets[k] <= 0 ? 0 : share >= 0.6 ? 3 : share >= 0.25 ? 2 : 1];
    }),
  ) as LoadMap;
}

/** Load levels for the last `days` days up to `now`. */
export const loadForDays = (sessions: Session[], days: number, now: number): LoadMap => loadLevels(setsPerMuscle(sessions, now - days * DAY_MS, now));
