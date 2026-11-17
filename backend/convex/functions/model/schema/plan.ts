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
  /** The activity this plan is for ("Gym", "Home", ...): a session with sets. */
  type: z.string().min(1).max(40),
  /** The focus this plan is for ("Upper", "Quick", ...), when it has one. */
  focus: z.string().min(1).max(40).optional(),
  createdAt: MsSchema,
  source: ProposalSourceSchema,
  rationale: z.string().max(200),
  exercises: z.array(PlanExerciseSchema),
});

/** What the plan_session job produces; code adds id, focus, createdAt, source. */
export const PlanDraftSchema = z.object({
  rationale: z.string().max(200),
  exercises: z.array(PlanExerciseSchema), // the 12 exercise / 10 set limits are applied in code afterwards
});

export const PredictionSchema = z.object({
  kind: z.enum(["gym", "activity"]),
  /** The activity ("Gym", "Home", "Run", ...). Taken from the log. At most 2 items per activity, 6 in total. */
  type: z.string().min(1).max(40),
  /** The advised flavour of that activity, when the log supports one. */
  focus: z.string().min(1).max(40).optional(),
  reason: z.string().max(80),
});

export type PlanSet = z.infer<typeof PlanSetSchema>;
export type PlanExercise = z.infer<typeof PlanExerciseSchema>;
export type Plan = z.infer<typeof PlanSchema>;
export type PlanDraft = z.infer<typeof PlanDraftSchema>;
export type Prediction = z.infer<typeof PredictionSchema>;

/** What the interpret_request job proposes for a typed start request (the shape the app reads, less the plan's id and times). */
export const StartProposalSchema = z
  .object({
    kind: z.enum(["gym", "activity"]),
    type: z.string().min(1).max(40),
    focus: z.string().min(1).max(40).optional(),
    minutes: z.number().int().positive().max(600).optional(),
    reason: z.string().max(80).optional(),
    plan: PlanDraftSchema.optional(),
  })
  .refine((p) => p.kind !== "gym" || p.plan !== undefined, { message: "a session with sets needs a plan", path: ["plan"] });

export type StartProposal = z.infer<typeof StartProposalSchema>;
