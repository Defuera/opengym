import { z } from "zod";
import { avoidedExercises } from "./rules/limits";
import { normName } from "./rules/muscles";
import { PlanExerciseSchema, type Limit, type PlanExercise } from "./schema";
import type { PlannedExercise } from "./openSession";

/**
 * The functions the coach may call in one chat turn (ADR-032), as zod schemas, and the pure logic behind them.
 * The model only names an action; server code checks it again against the data and does it (lib/coachToolsDb.ts).
 * In this step every tool is "applied at once and reported". No tool changes the place of the session.
 */

const Id = z.string().trim().min(1).max(100);
const ActionId = z.string().trim().min(1).max(40);
const Phrase = z.string().trim().min(1).max(200);

export const EVIDENCE = ["person_said", "seen_in_photo"] as const;

const action = <N extends string, A extends z.ZodTypeAny>(name: N, args: A) => z.object({ id: ActionId, name: z.literal(name), arguments: args });

export const UpdatePlaceArgs = z
  .object({ placeId: Id, add: Phrase.optional(), remove: Phrase.optional(), evidence: z.enum(EVIDENCE) })
  .refine((a) => a.add !== undefined || a.remove !== undefined, { message: "add or remove is needed" });

export const CoachActionSchema = z.discriminatedUnion("name", [
  action("update_place", UpdatePlaceArgs),
  action("replace_open_exercise", z.object({ exerciseId: Id, exercise: PlanExerciseSchema })),
  action("add_open_exercise", z.object({ exercise: PlanExerciseSchema, afterExerciseId: Id.optional() })),
  action("remove_open_exercise", z.object({ exerciseId: Id })),
  action("rebuild_open_session", z.object({ exercises: z.array(PlanExerciseSchema).min(1), focus: z.string().trim().min(1).max(40).optional(), planNote: z.string().max(400).optional() })),
]);

export const CoachQuestionSchema = z.object({
  text: z.string().trim().min(1).max(500),
  answers: z.array(z.object({ id: z.string().trim().min(1).max(40), label: z.string().trim().min(1).max(60) })).max(6).optional(),
});

/** What the model returns for one turn: the reply, the actions in order, and an optional question with quick answers. */
export const CoachTurnSchema = z.object({
  message: z.string().trim().min(1).max(4000),
  actions: z.array(CoachActionSchema).max(12).default([]),
  question: CoachQuestionSchema.optional(),
});

export type CoachAction = z.infer<typeof CoachActionSchema>;
export type CoachToolName = CoachAction["name"];
export type CoachTurn = z.infer<typeof CoachTurnSchema>;
export type CoachQuestion = z.infer<typeof CoachQuestionSchema>;

/** What one action did. "drafted" is for the later steps (draft until Done); no tool of this step returns it. */
export interface ActionResult {
  actionId: string;
  name: string;
  status: "applied" | "drafted" | "rejected";
  reason?: string;
}

/** The exercises an action writes. */
export function exercisesOf(a: CoachAction): PlanExercise[] {
  if (a.name === "replace_open_exercise" || a.name === "add_open_exercise") return [a.arguments.exercise];
  if (a.name === "rebuild_open_session") return a.arguments.exercises;
  return [];
}

/**
 * A rule the shape cannot hold, for the retry (ADR-004): action ids are unique, and no written exercise is one a limit marks avoid.
 * The executor checks both again in code.
 */
export function checkTurn(t: CoachTurn, limits: Limit[]): string | null {
  const ids = new Set<string>();
  for (const a of t.actions) {
    if (ids.has(a.id)) return `actions: the id "${a.id}" is used twice`;
    ids.add(a.id);
  }
  const avoid = avoidedExercises(limits);
  const hit = t.actions.flatMap(exercisesOf).find((e) => avoid.has(normName(e.name)));
  return hit ? `actions: "${hit.name}" is marked avoid` : null;
}

/** A plan exercise (zod shape) as an outside writer gives it to the open session. */
export function toPlanned(e: PlanExercise): PlannedExercise {
  const base = { name: e.name, ...(e.note ? { note: e.note } : {}) };
  return e.measure === "time" ? { ...base, measure: "time", sets: e.sets.map((s) => ({ ...s })) } : { ...base, sets: e.sets.map((s) => ({ reps: s.reps, kg: s.kg, max: s.max })) };
}

const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/**
 * The text of a place after one edit: `remove` is taken out wherever it stands (any case), lines left empty go;
 * `add` goes on a new line unless the text names it already. Pure.
 */
export function editPlaceText(text: string, add?: string, remove?: string): string {
  let lines = text.split("\n");
  if (remove?.trim()) {
    const re = new RegExp(escape(remove.trim()), "gi");
    lines = lines.map((l) => l.replace(re, "").replace(/\s*([,;])\s*[,;]\s*/g, "$1 ").replace(/^[\s,;.:-]+|[\s,;:-]+$/g, "")).filter((l) => l.trim());
  }
  const now = lines.join("\n").trim();
  const a = add?.trim();
  if (a && !now.toLowerCase().includes(a.toLowerCase())) return now ? `${now}\n${a}` : a;
  return now;
}
