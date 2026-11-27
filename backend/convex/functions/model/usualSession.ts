import { timezoneOf } from "./timezone";
import type { Session } from "./schema";

/** What the person usually does at this time of the week (ADR-042). Code computes it; the coach reads it as a fact. */
export interface UsualSession {
  /** "weekday morning", "weekend evening", or "weekday" when the slot had too few sessions. */
  when: string;
  sessions: number;
  usualMinutes: number;
  usualSets: number;
}

const DAY = 86_400_000;
export const USUAL_WINDOW_DAYS = 56;
export const USUAL_MIN_SESSIONS = 3;
const MIN_MINUTES = 10;
const MAX_MINUTES = 240;

const median = (xs: number[]): number => {
  const s = [...xs].sort((a, b) => a - b);
  const m = s.length >> 1;
  return s.length % 2 ? s[m]! : Math.round((s[m - 1]! + s[m]!) / 2);
};

/** The weekday-or-weekend kind and the part of day (morning before 12:00, afternoon before 17:00, else evening) of a time, in a time zone. */
export function slotOf(ms: number, timeZone?: string): { weekend: boolean; part: "morning" | "afternoon" | "evening" } {
  const zone = timezoneOf({ timezone: timeZone });
  const parts = new Intl.DateTimeFormat("en-GB", { timeZone: zone, weekday: "short", hour: "2-digit", hourCycle: "h23" }).formatToParts(new Date(ms));
  const weekday = parts.find((p) => p.type === "weekday")!.value;
  const hour = Number(parts.find((p) => p.type === "hour")!.value);
  return { weekend: weekday === "Sat" || weekday === "Sun", part: hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening" };
}

/**
 * The usual length and size of a session at the slot of `now`, from the finished sessions done in the app in the last 8 weeks
 * (an imported session holds message times, not the true length). Only a length of 10 to 240 minutes counts. With fewer than 3 sessions in the
 * slot, all sessions of the same kind of day (weekday or weekend) count; with fewer than 3 again, the result is null.
 */
export function usualSessionNow(sessions: Session[], now: number, timeZone?: string): UsualSession | null {
  const here = slotOf(now, timeZone);
  const rows = sessions
    .filter((s) => s.source !== "import" && s.endedAt > s.startedAt && s.endedAt <= now && s.endedAt > now - USUAL_WINDOW_DAYS * DAY)
    .map((s) => ({ minutes: Math.round((s.endedAt - s.startedAt) / 60000), sets: s.exercises.reduce((n, e) => n + e.sets.length, 0), slot: slotOf(s.startedAt, timeZone) }))
    .filter((r) => r.minutes >= MIN_MINUTES && r.minutes <= MAX_MINUTES);
  const kind = here.weekend ? "weekend" : "weekday";
  const sameDay = rows.filter((r) => r.slot.weekend === here.weekend);
  const exact = sameDay.filter((r) => r.slot.part === here.part);
  const [pick, when] = exact.length >= USUAL_MIN_SESSIONS ? [exact, `${kind} ${here.part}`] : [sameDay, kind];
  if (pick.length < USUAL_MIN_SESSIONS) return null;
  return { when, sessions: pick.length, usualMinutes: median(pick.map((r) => r.minutes)), usualSets: median(pick.map((r) => r.sets)) };
}
