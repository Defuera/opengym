import type { GoalInput, Rule } from "./schema";
import { GOAL_TITLE_MAX } from "./schema";
import { activityKey } from "./sessionShape";

/**
 * Pure helpers for the goal, limit and note parts of a draft (ADR-032, step D). They keep the goal the chat makes the same as the goal
 * the old form made: the structure fields (kind, exercise, targetKg, sessionsPerWeek) under GoalInputSchema, with the exercise a name of the log.
 */

/** Keeps the exercise only when it is a name of the log (the log's spelling); drops it otherwise. */
export function finalizeGoalExercise(g: GoalInput, exercises: string[]): GoalInput {
  const { exercise, ...rest } = g;
  const match = exercise === undefined ? undefined : exercises.find((n) => activityKey(n) === activityKey(exercise));
  return match === undefined ? rest : { ...rest, exercise: match };
}

const NUM = String.raw`(\d+(?:[.,]\d+)?)`;

/** The goal plain code makes from the person's words when no AI answer exists: the text as title, kind custom, "<number> kg" and "<n> times a week" when present. */
export function goalFromText(text: string): GoalInput {
  const kg = text.match(new RegExp(`${NUM}\\s*kg\\b`, "i"));
  const week = text.match(/(\d{1,2})\s*(?:x|times|sessions?|workouts?)\s*(?:a|per|\/|each)\s*week/i);
  const targetKg = kg ? Number(kg[1]!.replace(",", ".")) : undefined;
  const sessionsPerWeek = week ? Number(week[1]) : undefined;
  return {
    title: text.trim().slice(0, GOAL_TITLE_MAX),
    kind: "custom",
    ...(targetKg !== undefined && targetKg > 0 && targetKg <= 1000 ? { targetKg } : {}),
    ...(sessionsPerWeek !== undefined && sessionsPerWeek >= 1 && sessionsPerWeek <= 14 ? { sessionsPerWeek } : {}),
  };
}

/**
 * The rules of an edited limit. The coach reads only the kind and text of each rule (ADR-015: no exercise lists in a prompt), so a rule it sends back
 * with the same kind and text and no exercises keeps the exercises the person stored.
 */
export function mergeRules(old: Rule[], next: Rule[]): Rule[] {
  return next.map((r) => {
    if (r.exercises !== undefined) return r;
    const same = old.find((o) => o.kind === r.kind && o.text === r.text);
    return same?.exercises ? { ...r, exercises: same.exercises } : r;
  });
}
