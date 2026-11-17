import { v } from "convex/values";

export const itemSource = v.union(v.literal("user"), v.literal("ai"), v.literal("import"));
export const proposalSource = v.union(v.literal("ai"), v.literal("rules"));
export const goalKind = v.union(v.literal("strength"), v.literal("consistency"), v.literal("work_around"), v.literal("custom"));
export const goalStatus = v.union(v.literal("active"), v.literal("done"));
export const dashboardDays = v.union(v.literal(7), v.literal(30));

export const planSet = v.object({ reps: v.number(), kg: v.number(), max: v.boolean() });
export const planExercise = v.object({ name: v.string(), sets: v.array(planSet), note: v.optional(v.string()) });
export const prediction = v.object({ kind: v.union(v.literal("gym"), v.literal("activity")), type: v.string(), reason: v.string() });

/** Dashboard layout spec: which modules, in what order. Numbers are never stored (computed by code). */
export const moduleSpec = v.union(
  v.object({ type: v.literal("stat"), which: v.union(v.literal("sessions"), v.literal("active_days"), v.literal("sets"), v.literal("top_set")) }),
  v.object({ type: v.literal("goal_progress"), goalId: v.string() }),
  v.object({ type: v.literal("trend"), exercise: v.optional(v.string()) }),
  v.object({ type: v.literal("consistency") }),
  v.object({ type: v.literal("recent_sessions"), limit: v.optional(v.number()) }),
  v.object({ type: v.literal("note"), text: v.string() }),
);

export const importCounts = v.object({ sessions: v.number(), goals: v.number(), context: v.number() });
export const importStatus = v.union(v.literal("running"), v.literal("done"), v.literal("failed"));
