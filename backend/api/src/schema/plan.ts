import { z } from "zod";
import { IdSchema, MsSchema, ProposalSourceSchema } from "./common";

export const PlanSetSchema = z.object({
  reps: z.number().int().min(0).max(100),
  kg: z.number().min(0).max(500),
  max: z.boolean().default(false),
});

export const PlanExerciseSchema = z.object({
  name: z.string().min(1).max(60),
  sets: z.array(PlanSetSchema),
  note: z.string().max(120).optional(),
});

export const PlanSchema = z.object({
  id: IdSchema,
  type: z.string().min(1).max(40),
  createdAt: MsSchema,
  source: ProposalSourceSchema,
  rationale: z.string().max(200),
  exercises: z.array(PlanExerciseSchema),
});

/** What the plan_session job produces; code adds id, type, createdAt, source. */
export const PlanDraftSchema = z.object({
  rationale: z.string().max(200),
  exercises: z.array(PlanExerciseSchema), // the 12 exercise / 10 set limits are applied in code afterwards
});

export const PredictionSchema = z.object({
  kind: z.enum(["gym", "activity"]),
  type: z.string().min(1).max(40),
  reason: z.string().max(80),
});

export type PlanSet = z.infer<typeof PlanSetSchema>;
export type PlanExercise = z.infer<typeof PlanExerciseSchema>;
export type Plan = z.infer<typeof PlanSchema>;
export type PlanDraft = z.infer<typeof PlanDraftSchema>;
export type Prediction = z.infer<typeof PredictionSchema>;
