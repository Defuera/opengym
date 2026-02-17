import { v } from "convex/values";
import { mutation, query } from "./_generated/server";

// Get exercises for a session
export const listBySession = query({
  args: { sessionId: v.id("sessions") },
  handler: async (ctx, args) => {
    const exercises = await ctx.db
      .query("exercises")
      .withIndex("by_session", (q) => q.eq("sessionId", args.sessionId))
      .collect();

    return exercises.sort((a, b) => a.order - b.order);
  },
});

// Add a new exercise to a session
export const addToSession = mutation({
  args: {
    sessionId: v.id("sessions"),
    name: v.string(),
    muscleGroup: v.string(),
    sets: v.array(
      v.object({
        reps: v.number(),
        weight: v.number(),
        order: v.number(),
      })
    ),
  },
  handler: async (ctx, args) => {
    // Get existing exercises to determine the order
    const existingExercises = await ctx.db
      .query("exercises")
      .withIndex("by_session", (q) => q.eq("sessionId", args.sessionId))
      .collect();

    const order = existingExercises.length;

    // Create the exercise
    const exerciseId = await ctx.db.insert("exercises", {
      sessionId: args.sessionId,
      name: args.name,
      muscleGroup: args.muscleGroup,
      order,
    });

    // Create the sets
    for (const setData of args.sets) {
      await ctx.db.insert("sets", {
        exerciseId,
        reps: setData.reps,
        weight: setData.weight,
        order: setData.order,
      });
    }

    // Update session's updatedAt timestamp
    await ctx.db.patch(args.sessionId, {
      updatedAt: Date.now(),
    });

    return exerciseId;
  },
});
