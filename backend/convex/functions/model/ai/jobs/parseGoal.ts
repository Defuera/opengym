import { z } from "zod";
import type { JobDef } from "../runJob";
import { dataPrompt, systemPrompt } from "../promptRules";
import { GoalKindSchema } from "../../schema";
import { activityKey } from "../../sessionShape";

/**
 * parse_goal: reads the structure out of the text of a goal the user typed (kind, exercise, target weight, sessions per week).
 *
 * ADR-002: this is derived structure of the user's own text, not a new fact. The goal itself (title, status) is the user's and
 * is stored first, as typed. The job never changes the title or the status and it adds nothing the text does not say.
 * ADR-004 pipeline: prompt, provider, JSON, zod, one retry, plain code fallback.
 */
export interface ParseGoalInput {
  /** The goal as the user typed it. */
  text: string;
  /** Exercise names of the log (distinct, most recent first). */
  exercises: string[];
}

const opt = <T extends z.ZodType>(s: T) => s.nullish().transform((v) => v ?? undefined);

export const ParsedGoalSchema = z.object({
  kind: GoalKindSchema,
  exercise: opt(z.string().trim().min(1).max(60)),
  targetKg: opt(z.number().gt(0).max(1000)),
  sessionsPerWeek: opt(z.number().int().min(1).max(14)),
});
export type ParsedGoal = z.infer<typeof ParsedGoalSchema>;

const MAX_NAMES = 150;

/** Keeps the exercise only when it is a name of the log (the log's spelling); drops it otherwise. */
export function finalizeParsedGoal(g: ParsedGoal, exercises: string[]): ParsedGoal {
  const match = g.exercise === undefined ? undefined : exercises.find((n) => activityKey(n) === activityKey(g.exercise!));
  return { ...g, exercise: match };
}

const NUM = String.raw`(\d+(?:[.,]\d+)?)`;

/** Plain-code reading: "<number> kg" and "<n> times/sessions a week". Finds nothing else; the kind stays custom. */
export function parseGoalFallback(text: string): ParsedGoal {
  const kg = text.match(new RegExp(`${NUM}\\s*kg\\b`, "i"));
  const week = text.match(/(\d{1,2})\s*(?:x|times|sessions?|workouts?)\s*(?:a|per|\/|each)\s*week/i);
  const targetKg = kg ? Number(kg[1]!.replace(",", ".")) : undefined;
  const sessionsPerWeek = week ? Number(week[1]) : undefined;
  return {
    kind: "custom",
    ...(targetKg !== undefined && targetKg > 0 && targetKg <= 1000 ? { targetKg } : {}),
    ...(sessionsPerWeek !== undefined && sessionsPerWeek >= 1 && sessionsPerWeek <= 14 ? { sessionsPerWeek } : {}),
  } as ParsedGoal;
}

export const parseGoalJob: JobDef<ParseGoalInput, ParsedGoal> = {
  name: "parse_goal",
  description: "The structure of a goal text: kind, an exercise of the log, target weight in kg, sessions per week. Only what the text says.",
  fallbackDescription: "Kind custom; a number before kg and a number before times/sessions a week, when the text has them.",
  json: true,
  maxTokens: 300,
  output: ParsedGoalSchema as unknown as z.ZodType<ParsedGoal>,
  build: (i) => ({
    system: systemPrompt(
      "parse_goal",
      `Read the structure out of one goal the user wrote. Use only what the text says; never add a number it does not hold. kind: "strength" (lift a weight, a rep or a target on one exercise), "consistency" (train a number of times in a period), else "custom". exercise: a name from the list "exercises" when the goal is about one of them, else leave it out. targetKg: the target weight in kg. sessionsPerWeek: whole sessions per week.`,
      `{"kind": "strength"|"consistency"|"custom", "exercise"?: string (a name from exercises), "targetKg"?: number, "sessionsPerWeek"?: integer}`,
    ),
    messages: [{ role: "user", content: dataPrompt("Read this goal.", { goal: i.text.slice(0, 300), exercises: i.exercises.slice(0, MAX_NAMES) }) }],
  }),
  fallback: (i) => parseGoalFallback(i.text),
};
