import { v } from "convex/values";
import { mutation, query } from "./_generated/server";

// Get sets for an exercise
export const listByExercise = query({
  args: { exerciseId: v.id("exercises") },
  handler: async (ctx, args) => {
    const sets = await ctx.db
      .query("sets")
      .withIndex("by_exercise", (q) => q.eq("exerciseId", args.exerciseId))
      .collect();

    return sets.sort((a, b) => a.order - b.order);
  },
});

// Update a set's reps and/or weight
export const update = mutation({
  args: {
    id: v.id("sets"),
    reps: v.optional(v.number()),
    weight: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const updates: { reps?: number; weight?: number } = {};
    if (args.reps !== undefined) updates.reps = args.reps;
    if (args.weight !== undefined) updates.weight = args.weight;

    await ctx.db.patch(args.id, updates);
  },
});
