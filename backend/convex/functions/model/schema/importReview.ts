import { z } from "zod";
import { IdSchema, MsSchema } from "./common";

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

export const ReviewSchema = z.object({
  sessionId: z.string(),
  source: z.enum(["ai", "rules"]),
  summary: z.string().max(400),
  changes: z.array(z.string()).max(5),
});

export const ReviewDraftSchema = ReviewSchema.omit({ sessionId: true, source: true });

export type ImportJob = z.infer<typeof ImportJobSchema>;
export type Review = z.infer<typeof ReviewSchema>;
export type ReviewDraft = z.infer<typeof ReviewDraftSchema>;
