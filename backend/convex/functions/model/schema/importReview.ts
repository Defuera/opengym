import { z } from "zod";
import { IdSchema, MsSchema } from "./common";
import { ContextInputSchema, GoalInputSchema } from "./goalContext";
import { SetEntrySchema, TimeExerciseSchema } from "./session";

export const ImportJobSchema = z.object({
  id: IdSchema,
  status: z.enum(["running", "done", "failed"]),
  total: z.number().int().nonnegative(),
  processed: z.number().int().nonnegative(),
  counts: z.object({
    sessions: z.number().int(),
    goals: z.number().int(),
    context: z.number().int(),
  }),
  notes: z.array(z.string()),
  createdAt: MsSchema,
});

/** The question of a debrief (ADR-041), as stored and shown: the answers have ids made in code. */
export const ReviewQuestionSchema = z.object({
  text: z.string().min(1).max(120),
  answers: z.array(z.object({ id: z.string().min(1).max(20), label: z.string().min(1).max(24) })).min(2).max(4),
});

export const REVIEW_MESSAGE_MAX = 500;

/**
 * A review as stored. A NEW review (ADR-041) has `message` and maybe `question`. An OLD one has `summary` and `changes`
 * (no longer written, still read and shown). A stored review has either.
 */
export const ReviewSchema = z.object({
  sessionId: z.string(),
  source: z.enum(["ai", "rules"]),
  summary: z.string().max(400).optional(),
  changes: z.array(z.string()).max(5).optional(),
  message: z.string().max(REVIEW_MESSAGE_MAX).optional(),
  question: ReviewQuestionSchema.optional(),
});

/** What the review job returns: the debrief message, and a question with 2 to 4 short answer labels (the ids are made in code). */
export const ReviewDraftSchema = z.object({
  message: z.string().min(1).max(REVIEW_MESSAGE_MAX),
  question: z.object({ text: z.string().min(1).max(120), answers: z.array(z.string().min(1).max(24)).min(2).max(4) }).optional(),
});

const ImportExerciseSchema = z.union([
  z.object({
    name: z.string().min(1).max(60),
    measure: z.literal("sets").optional(),
    sets: z.array(SetEntrySchema.extend({ max: z.boolean().default(false) })).max(12),
  }),
  TimeExerciseSchema,
]);

/** A session as the import job may produce it; the date is optional on purpose (ISO string). */
export const ImportSessionDraftSchema = z.object({
  kind: z.enum(["gym", "activity"]),
  /** The activity. Gym sessions may still arrive as type "Upper" (old shape); code normalises them. */
  type: z.string().min(1).max(40),
  focus: z.string().min(1).max(40).optional(),
  date: z.string().optional(),
  exercises: z.array(ImportExerciseSchema).max(15).default([]),
  minutes: z.number().int().nonnegative().optional(),
  distanceKm: z.number().nonnegative().optional(),
  note: z.string().optional(),
});

export const ImportOutputSchema = z.object({
  sessions: z.array(ImportSessionDraftSchema).default([]),
  goals: z.array(GoalInputSchema).default([]),
  context: z.array(ContextInputSchema).default([]),
  notes: z.array(z.string()).default([]),
});

export type ImportJob = z.infer<typeof ImportJobSchema>;
export type Review = z.infer<typeof ReviewSchema>;
export type ReviewDraft = z.infer<typeof ReviewDraftSchema>;
export type ImportSessionDraft = z.infer<typeof ImportSessionDraftSchema>;
export type ImportOutput = z.infer<typeof ImportOutputSchema>;
