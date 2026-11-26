import { timezoneOf } from "./timezone";

/** Day arithmetic in a time zone (default: `timezoneOf()`, the deployment's zone; the callers pass the zone of the user, ADR-039). Used by the parse_log job (ADR-018). */

const DAY = 86_400_000;
const MAX_DAYS_BACK = 366;

export const appTimeZone = (): string => timezoneOf();

/** "YYYY-MM-DD" of a moment in the time zone. */
export const localDay = (ms: number, timeZone = appTimeZone()): string =>
  new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date(ms));

/** "2026-11-18 (Wednesday)": today as the job input carries it. */
export const dayWithWeekday = (ms: number, timeZone = appTimeZone()): string =>
  `${localDay(ms, timeZone)} (${new Date(ms).toLocaleDateString("en-GB", { weekday: "long", timeZone })})`;

const dayNumber = (day: string): number => Date.UTC(Number(day.slice(0, 4)), Number(day.slice(5, 7)) - 1, Number(day.slice(8, 10))) / DAY;

const minuteOfDay = (ms: number, timeZone: string): number => {
  const [h, m] = new Intl.DateTimeFormat("en-GB", { timeZone, hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(ms)).split(":");
  return (Number(h) % 24) * 60 + Number(m);
};

/**
 * Moves `at` to the calendar day `day` ("YYYY-MM-DD") and keeps the time of day. A day that is not a date, a day after today
 * and a day more than a year back leave `at` as it is.
 */
export function shiftToDay(at: number, day: string, now: number, timeZone = appTimeZone()): number {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) return at;
  const target = dayNumber(day);
  if (Number.isNaN(target) || localDay(target * DAY + DAY / 2, "UTC") !== day) return at; // not a real date (2026-02-31)
  const today = dayNumber(localDay(now, timeZone));
  if (target > today || today - target > MAX_DAYS_BACK) return at;
  const moved = at + (target - dayNumber(localDay(at, timeZone))) * DAY;
  // A change of summer time moves the clock by an hour between the two days: put the time of day back.
  let drift = minuteOfDay(at, timeZone) - minuteOfDay(moved, timeZone);
  if (drift > 720) drift -= 1440;
  if (drift < -720) drift += 1440;
  return moved + drift * 60_000;
}
