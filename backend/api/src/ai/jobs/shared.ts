import type { ContextItem, Goal, Session } from "../../schema";
import { fmtKg } from "../../rules/util";

/** Compact, factual view of the log for prompts. */
export function logForPrompt(sessions: Session[], limit = 12) {
  return sessions.slice(-limit).map((s) => ({
    date: new Date(s.endedAt).toISOString().slice(0, 10),
    kind: s.kind,
    type: s.type,
    exercises: s.exercises.map((e) => ({ name: e.name, sets: e.sets.map((x) => `${x.reps}x${fmtKg(x.kg)}${x.max ? " max" : ""}`).join(", ") })),
    minutes: s.minutes,
    distanceKm: s.distanceKm,
  }));
}

export const goalsForPrompt = (goals: Goal[]) =>
  goals.map((g) => ({ id: g.id, title: g.title, kind: g.kind, exercise: g.exercise, targetKg: g.targetKg, sessionsPerWeek: g.sessionsPerWeek, status: g.status }));

export const contextForPrompt = (items: ContextItem[]) => items.filter((c) => c.active).map((c) => ({ topic: c.topic, text: c.text }));
