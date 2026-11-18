import { coachPicture } from "./ai/jobs/coachPicture";
import { type ParseLogInput, usualSets } from "./ai/jobs/parseLog";
import { dayWithWeekday } from "./logDate";
import type { Session } from "./schema";

export const MAX_KNOWN = 150;

/**
 * The parse_log job input for the text of one session, and what the finishing step needs (pure; the Convex query reads the log).
 * `all` is the FULL history, oldest first; `doc` is the session the text belongs to.
 */
export function buildParseLogInput(all: Session[], doc: { type: string; startedAt: number }, text: string, now: number) {
  const known = coachPicture(all, [], [], [], [], now).exercisesTheUserKnows.slice(0, MAX_KNOWN);
  const job: ParseLogInput = {
    activity: doc.type,
    text,
    today: dayWithWeekday(now),
    exercisesTheUserKnows: known.map((e) => ({ name: e.name, lastSets: e.lastSets, ...(e.measure ? { measure: e.measure } : {}) })),
  };
  return { job, usual: [...usualSets(all).values()], at: doc.startedAt, now };
}
