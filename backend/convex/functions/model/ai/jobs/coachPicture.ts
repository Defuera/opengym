import { limitsForPrompt } from "../../rules/limits";
import { musclesFor } from "../../rules/muscles";
import type { Entry, Goal, Limit, Session } from "../../schema";
import { entriesForPrompt } from "../../entryContext";
import { timeText } from "../../rules/util";
import { topKg, type ContextItem } from "../../schema";
import { contextForPrompt, goalsForPrompt, localTime } from "./shared";

const DAY = 86_400_000;
const day = (ms: number) => new Date(ms).toISOString().slice(0, 10);
const setsText = (sets: ({ reps: number; kg: number } | { minutes: number; distanceKm?: number })[]) =>
  sets.map((x) => ("kg" in x ? `${x.reps}x${x.kg}` : timeText(x))).join(", ");

/**
 * The picture of the user a coach needs to build one session: who trains, what they can do (every exercise of the
 * full log with its last sets and best weight), what the last weeks looked like, the recent sessions with their
 * notes, the goals in order, the limits, the notes, the log entries of the last week. Plain code, no AI. Never holds records (ADR-015).
 */
export function coachPicture(all: Session[], goals: Goal[], context: ContextItem[], limits: Limit[], entries: Entry[], now: number) {
  const gym = all.filter((s) => s.kind === "gym");
  const byName = new Map<string, { name: string; times: number; last: Session; lastSets: string; bestKg: number; time: boolean }>();
  for (const s of gym) {
    for (const e of s.exercises) {
      if (e.sets.length === 0) continue;
      const best = topKg(e);
      const time = e.measure === "time";
      const row = byName.get(e.name);
      if (!row) byName.set(e.name, { name: e.name, times: 1, last: s, lastSets: setsText(e.sets), bestKg: best, time });
      else Object.assign(row, { times: row.times + 1, last: s, lastSets: setsText(e.sets), bestKg: Math.max(row.bestKg, best), time });
    }
  }
  const exercises = [...byName.values()]
    .sort((a, b) => b.last.endedAt - a.last.endedAt)
    .map((r) => ({ name: r.name, area: musclesFor(r.name).primary, timesLogged: r.times, lastDone: day(r.last.endedAt), lastSets: r.lastSets, bestKg: r.bestKg, ...(r.time ? { measure: "time" as const } : {}) }));
  const weeks = [0, 1, 2, 3].map((w) => {
    const to = now - w * 7 * DAY;
    const inWeek = all.filter((s) => s.endedAt > to - 7 * DAY && s.endedAt <= to);
    return { daysAgo: `${w * 7}-${w * 7 + 6}`, sessions: inWeek.map((s) => (s.focus ? `${s.type} ${s.focus}` : s.type)) };
  });
  const recent = all.filter((s) => s.endedAt > now - 21 * DAY).slice(-12).map((s) => ({
    date: day(s.endedAt),
    ...(s.endedAt > s.startedAt || s.source !== "import" ? { start: localTime(s.startedAt) } : {}),
    type: s.type,
    focus: s.focus,
    // A comment is what the person wrote about the exercise in that session (ADR-029), word for word.
    exercises: s.exercises.map((e) => `${e.name}: ${setsText(e.sets)}${e.comment ? ` (comment from the person: "${e.comment}")` : ""}`),
    minutes: s.minutes,
    distanceKm: s.distanceKm,
    note: s.note,
  }));
  return {
    today: `${day(now)} (${new Date(now).toLocaleDateString("en-GB", { weekday: "long", timeZone: process.env.APP_TIMEZONE || "UTC" })})`,
    timeNow: localTime(now),
    trainingSince: all.length > 0 ? day(all[0]!.startedAt) : null,
    sessionsLogged: all.length,
    goalsInOrderOfPriority: goalsForPrompt(goals.filter((g) => g.status === "active")),
    limits: limitsForPrompt(limits),
    notesFromTheUser: contextForPrompt(context),
    logEntriesFromTheUser: entriesForPrompt(entries),
    last4Weeks: weeks,
    recentSessions: recent,
    exercisesTheUserKnows: exercises,
  };
}
