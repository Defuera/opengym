import { z } from "zod";
import { IdSchema, MsSchema } from "./common";
import { ContextInputSchema, GoalInputSchema } from "./goal-context";
import { ExerciseSchema } from "./session";

export const MAX_STRUCTURED_SESSIONS = 2000;

/** A ready session. The server adds source and importId, then checks the result with SessionSchema. */
export const StructuredSessionSchema = z.object({
  id: IdSchema.optional(),
  kind: z.enum(["gym", "activity"]),
  type: z.string(),
  startedAt: MsSchema,
  endedAt: MsSchema,
  exercises: z.array(ExerciseSchema).default([]),
  minutes: z.number().optional(),
  distanceKm: z.number().optional(),
  note: z.string().optional(),
});

/** Items stay unknown here so each one can be reported by its index. */
export const StructuredImportBodySchema = z.object({
  sessions: z.array(z.unknown()).max(MAX_STRUCTURED_SESSIONS),
  goals: z.array(z.unknown()).default([]),
  context: z.array(z.unknown()).default([]),
  note: z.string().max(200).optional(),
});

export { ContextInputSchema, GoalInputSchema };
