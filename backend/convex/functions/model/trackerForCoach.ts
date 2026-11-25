import type { TrackerDay, TrackerWorkout } from "./schema";
import { localTime } from "./ai/jobs/shared";
import { localDate } from "./program";

const DAY = 86_400_000;
const MIN = 60_000;
export const TRACKER_PROMPT_DAYS = 7;
export const TRACKER_PROMPT_WORKOUT_DAYS = 14;
export const TRACKER_PROMPT_WORKOUTS_MAX = 30;
/** A tracker workout and a logged session are the same workout when their times overlap, give or take this much. */
export const OVERLAP_MARGIN_MS = 15 * MIN;

/** What the server holds of the phone's health store, as the jobs read it (ADR-036). */
export interface TrackerForCoach {
  days: TrackerDay[];
  workouts: TrackerWorkout[];
}

/** What a prompt carries: short lines, missing values left out. */
export interface TrackerBlock {
  last7Days: string[];
  workoutsLast14Days: string[];
  /** A tracker workout that is a logged session seen by the tracker: only the tracker's own numbers, attached to that session. */
  onLoggedSessions?: string[];
}

type SessionTimes = { startedAt: number; endedAt: number; type: string; focus?: string };

const hours = (min: number) => `${Math.round((min / 60) * 10) / 10}`;

function dayLine(d: TrackerDay): string | null {
  const parts: string[] = [];
  if (d.sleepMinutes !== undefined) {
    const stages = [["light", d.sleepLightMinutes], ["deep", d.sleepDeepMinutes], ["REM", d.sleepRemMinutes]].filter((x): x is [string, number] => x[1] !== undefined);
    parts.push(`sleep ${hours(d.sleepMinutes)} h${stages.length ? ` (${stages.map(([n, m]) => `${n} ${hours(m)}`).join(", ")})` : ""}`);
  }
  if (d.restingHeartRate !== undefined) parts.push(`resting heart rate ${d.restingHeartRate}`);
  if (d.steps !== undefined) parts.push(`steps ${d.steps}`);
  if (d.activeEnergyKcal !== undefined) parts.push(`active ${Math.round(d.activeEnergyKcal)} kcal`);
  return parts.length ? `${d.date}: ${parts.join(", ")}` : null;
}

function workoutLine(w: TrackerWorkout): string {
  const parts = [`${w.minutes} min`];
  if (w.distanceKm !== undefined) parts.push(`${Math.round(w.distanceKm * 10) / 10} km`);
  if (w.avgHeartRate !== undefined) parts.push(`avg heart rate ${w.avgHeartRate}`);
  return `${localDate(w.startedAt)} ${localTime(w.startedAt)} ${w.type}, ${parts.join(", ")}`;
}

const overlaps = (w: TrackerWorkout, s: SessionTimes) => w.startedAt < s.endedAt + OVERLAP_MARGIN_MS && w.endedAt > s.startedAt - OVERLAP_MARGIN_MS;

/**
 * The tracker block of a prompt (pure, ADR-036): the last 7 days as short lines and the tracker workouts of the last 14 days. A tracker
 * workout that overlaps a logged session in time is the same workout: it is not listed as a workout; its average heart rate and energy
 * go on a line about that session instead (when it has any). Null when there is nothing to say. `sessions` are the logged ones (any order).
 */
export function trackerForPrompt(tracker: TrackerForCoach | undefined, sessions: SessionTimes[], now: number): TrackerBlock | null {
  if (!tracker) return null;
  const from = localDate(now - (TRACKER_PROMPT_DAYS - 1) * DAY);
  const to = localDate(now);
  const last7Days = tracker.days
    .filter((d) => d.date >= from && d.date <= to)
    .sort((a, b) => a.date.localeCompare(b.date))
    .map(dayLine)
    .filter((l): l is string => l !== null);
  const own: string[] = [];
  const onSessions: string[] = [];
  const recent = tracker.workouts.filter((w) => w.startedAt >= now - TRACKER_PROMPT_WORKOUT_DAYS * DAY && w.endedAt <= now).sort((a, b) => a.startedAt - b.startedAt);
  for (const w of recent) {
    const s = sessions.find((x) => overlaps(w, x));
    if (!s) {
      own.push(workoutLine(w));
      continue;
    }
    const numbers = [w.avgHeartRate !== undefined ? `avg heart rate ${w.avgHeartRate}` : "", w.energyKcal !== undefined ? `${Math.round(w.energyKcal)} kcal` : ""].filter(Boolean);
    if (numbers.length) onSessions.push(`${localDate(s.endedAt)} ${s.type}${s.focus ? ` ${s.focus}` : ""}: tracker saw ${numbers.join(", ")}`);
  }
  const workoutsLast14Days = own.slice(-TRACKER_PROMPT_WORKOUTS_MAX);
  if (!last7Days.length && !workoutsLast14Days.length && !onSessions.length) return null;
  return { last7Days, workoutsLast14Days, ...(onSessions.length ? { onLoggedSessions: onSessions } : {}) };
}
