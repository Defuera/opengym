import { z } from "zod";

export const DashboardModuleSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("stat"), label: z.string(), value: z.string(), highlighted: z.boolean() }),
  z.object({
    type: z.literal("goal_progress"),
    goalId: z.string(),
    title: z.string(),
    current: z.string(),
    target: z.string(),
    fraction: z.number().min(0).max(1).nullable(),
  }),
  z.object({
    type: z.literal("trend"),
    title: z.string(),
    unit: z.string(),
    points: z.array(z.object({ t: z.number(), value: z.number() })),
  }),
  z.object({ type: z.literal("consistency"), title: z.string(), days: z.array(z.boolean()) }),
  z.object({
    type: z.literal("recent_sessions"),
    items: z.array(z.object({ title: z.string(), subtitle: z.string(), trailing: z.string() })),
  }),
  z.object({ type: z.literal("note"), text: z.string() }),
]);

export const DashboardSchema = z.object({
  days: z.union([z.literal(7), z.literal(30)]),
  source: z.enum(["ai", "rules"]),
  modules: z.array(DashboardModuleSchema).max(10),
});

/** What the AI may choose: which modules, order, parameters. Never numbers. */
export const ModuleSpecSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("stat"), which: z.enum(["sessions", "active_days", "sets", "top_set"]) }),
  z.object({ type: z.literal("goal_progress"), goalId: z.string() }),
  z.object({ type: z.literal("trend"), exercise: z.string().max(60).optional() }),
  z.object({ type: z.literal("consistency") }),
  z.object({ type: z.literal("recent_sessions"), limit: z.number().int().min(1).max(10).optional() }),
  z.object({ type: z.literal("note"), text: z.string().max(200) }),
]);

export const DashboardSpecDraftSchema = z.object({ modules: z.array(ModuleSpecSchema).max(10) });

export const DashboardSpecSchema = DashboardSpecDraftSchema.extend({
  source: z.enum(["ai", "rules"]),
});

export type DashboardModule = z.infer<typeof DashboardModuleSchema>;
export type Dashboard = z.infer<typeof DashboardSchema>;
export type ModuleSpec = z.infer<typeof ModuleSpecSchema>;
export type DashboardSpecDraft = z.infer<typeof DashboardSpecDraftSchema>;
export type DashboardSpec = z.infer<typeof DashboardSpecSchema>;
