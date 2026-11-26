import { coachPicture } from "./ai/jobs/coachPicture";
import { type ParseLogInput, usualSets } from "./ai/jobs/parseLog";
import { dayWithWeekday } from "./logDate";
import { timezoneOf } from "./timezone";
import type { Session } from "./schema";

export const MAX_KNOWN = 150;

/**
 * The parse_log job input for the text of one session, and what the finishing step needs (pure; the Convex query reads the log).
 * `all` is the FULL history, oldest first; `doc` is the session the text belongs to.
 */
export function buildParseLogInput(all: Session[], doc: { type: string; startedAt: number }, text: string, now: number, timeZone?: string) {
  const known = coachPicture(all, [], [], [], [], now, undefined, timeZone).exercisesTheUserKnows.slice(0, MAX_KNOWN);
  const job: ParseLogInput = {
    activity: doc.type,
    text,
    today: dayWithWeekday(now, timeZone ?? timezoneOf()),
    exercisesTheUserKnows: known.map((e) => ({ name: e.name, lastSets: e.lastSets, ...(e.measure ? { measure: e.measure } : {}) })),
  };
  return { job, usual: [...usualSets(all).values()], at: doc.startedAt, now, timeZone: timeZone ?? timezoneOf() };
}
