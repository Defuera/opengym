import type { ContextItem, Goal, Session } from "../../schema";
import { fmtKg, timeText } from "../../rules/util";

/** Compact, factual view of the log for prompts. */
/** "HH:MM" in the owner's time zone (env APP_TIMEZONE, an IANA name; UTC when not set). */
export function localTime(ms: number): string {
  return new Intl.DateTimeFormat("en-GB", { timeZone: process.env.APP_TIMEZONE || "UTC", hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(ms));
}

export function logForPrompt(sessions: Session[], limit = 12) {
  return sessions.slice(-limit).map((s) => ({
    date: new Date(s.endedAt).toISOString().slice(0, 10),
    // Start time and length teach the coach the user's habits (time of day, usual length). Left out when not known:
    // an imported session with no time has the same start and end.
    // The length is given only for a session done in the app: an imported one holds message times, not the true length.
    ...(s.endedAt > s.startedAt || s.source !== "import" ? { start: localTime(s.startedAt) } : {}),
    ...(s.endedAt > s.startedAt && s.source !== "import" ? { durationMin: Math.round((s.endedAt - s.startedAt) / 60000) } : {}),
    kind: s.kind,
    type: s.type,
    focus: s.focus,
    exercises: s.exercises.map((e) => ({ name: e.name, sets: e.sets.map((x) => ("kg" in x ? `${x.reps}x${fmtKg(x.kg)}${x.max ? " max" : ""}` : timeText(x))).join(", "), ...(e.comment ? { commentFromThePerson: e.comment } : {}) })),
    minutes: s.minutes,
    distanceKm: s.distanceKm,
  }));
}

export const goalsForPrompt = (goals: Goal[]) =>
  goals.map((g) => ({ id: g.id, title: g.title, kind: g.kind, exercise: g.exercise, targetKg: g.targetKg, sessionsPerWeek: g.sessionsPerWeek, status: g.status }));

export const contextForPrompt = (items: ContextItem[]) => items.filter((c) => c.active).map((c) => ({ topic: c.topic, text: c.text }));

export { limitsForPrompt } from "../../rules/limits";

/** An activity of the log with its kind and foci, as a prompt carries it. */
export interface KnownActivity {
  type: string;
  kind: "gym" | "activity";
  foci: string[];
}

/** One sentence for every plan-writing prompt: work measured in time uses minutes, not reps. */
export const TIME_RULE = "For work that is measured in time (for example a bike or a hold), use measure time with minutes, not reps.";
