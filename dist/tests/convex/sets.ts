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

// Update a set's reps, weight, and/or status
export const update = mutation({
  args: {
    id: v.id("sets"),
    reps: v.optional(v.number()),
    weight: v.optional(v.number()),
    status: v.optional(
      v.union(v.literal("todo"), v.literal("later"), v.literal("complete"))
    ),
  },
  handler: async (ctx, args) => {
    const updates: { reps?: number; weight?: number; status?: "todo" | "later" | "complete" } = {};
    if (args.reps !== undefined) updates.reps = args.reps;
    if (args.weight !== undefined) updates.weight = args.weight;
    if (args.status !== undefined) updates.status = args.status;

    await ctx.db.patch(args.id, updates);
  },
});

// Create a new set for an exercise
export const create = mutation({
  args: {
    exerciseId: v.id("exercises"),
    reps: v.number(),
    weight: v.number(),
    order: v.number(),
  },
  handler: async (ctx, args) => {
    const setId = await ctx.db.insert("sets", {
      exerciseId: args.exerciseId,
      reps: args.reps,
      weight: args.weight,
      order: args.order,
      status: "todo",
    });

    return setId;
  },
});

// Delete a set
export const remove = mutation({
  args: {
    id: v.id("sets"),
  },
  handler: async (ctx, args) => {
    await ctx.db.delete(args.id);
  },
});
