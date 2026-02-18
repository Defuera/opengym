import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { Id } from "./_generated/dataModel";

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
        status: "todo",
      });
    }

    // Update session's updatedAt timestamp
    await ctx.db.patch(args.sessionId, {
      updatedAt: Date.now(),
    });

    return exerciseId;
  },
});

// Get last recorded values for an exercise by name
export const getLastValuesByName = query({
  args: {
    userId: v.id("users"),
    exerciseName: v.string(),
  },
  handler: async (ctx, args) => {
    // Find all exercises with this name for this user
    const userSessions = await ctx.db
      .query("sessions")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .filter((q) => q.eq(q.field("status"), "completed"))
      .collect();

    if (userSessions.length === 0) {
      return null;
    }

    // Find all exercises with this name in completed sessions
    let latestExercise: { _id: Id<"exercises">; sessionId: Id<"sessions"> } | null = null;
    let latestSessionDate = 0;

    for (const session of userSessions) {
      const exercises = await ctx.db
        .query("exercises")
        .withIndex("by_session", (q) => q.eq("sessionId", session._id))
        .filter((q) => q.eq(q.field("name"), args.exerciseName))
        .collect();

      if (exercises.length > 0 && session.date > latestSessionDate) {
        latestSessionDate = session.date;
        latestExercise = exercises[0];
      }
    }

    if (!latestExercise) {
      return null;
    }

    // Get the last set from this exercise
    const sets = await ctx.db
      .query("sets")
      .withIndex("by_exercise", (q) => q.eq("exerciseId", latestExercise._id))
      .collect();

    if (sets.length === 0) {
      return null;
    }

    // Return the last set's values
    const lastSet = sets.sort((a, b) => b.order - a.order)[0];
    return {
      reps: lastSet.reps,
      weight: lastSet.weight,
    };
  },
});
