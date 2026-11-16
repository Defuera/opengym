import { z } from "zod";
import { IdSchema, ItemSourceSchema, MsSchema } from "./common";

export const GoalKindSchema = z.enum(["strength", "consistency", "work_around", "custom"]);

export const GoalSchema = z.object({
  id: IdSchema,
  title: z.string().min(1).max(80),
  kind: GoalKindSchema,
  exercise: z.string().optional(),
  targetKg: z.number().optional(),
  sessionsPerWeek: z.number().int().optional(),
  status: z.enum(["active", "done"]),
  source: ItemSourceSchema,
  threadId: z.string().optional(),
  importId: z.string().optional(),
  createdAt: MsSchema,
});

export const GoalInputSchema = z.object({
  title: z.string().min(1).max(80),
  kind: GoalKindSchema,
  exercise: z.string().min(1).max(60).optional(),
  targetKg: z.number().min(0).max(1000).optional(),
  sessionsPerWeek: z.number().int().min(1).max(14).optional(),
});

export const GoalPatchSchema = GoalInputSchema.partial().extend({
  status: z.enum(["active", "done"]).optional(),
});

export const ContextItemSchema = z.object({
  id: IdSchema,
  text: z.string().min(1).max(300),
  topic: z.string().min(1).max(30),
  active: z.boolean(),
  source: ItemSourceSchema,
  threadId: z.string().optional(),
  importId: z.string().optional(),
  createdAt: MsSchema,
});

export const ContextInputSchema = z.object({
  text: z.string().min(1).max(300),
  topic: z.string().min(1).max(30),
});

export const ContextPatchSchema = z.object({
  active: z.boolean().optional(),
  text: z.string().min(1).max(300).optional(),
});

export type Goal = z.infer<typeof GoalSchema>;
export type GoalInput = z.infer<typeof GoalInputSchema>;
export type GoalPatch = z.infer<typeof GoalPatchSchema>;
export type ContextItem = z.infer<typeof ContextItemSchema>;
export type ContextInput = z.infer<typeof ContextInputSchema>;
export type ContextPatch = z.infer<typeof ContextPatchSchema>;
