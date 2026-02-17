import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { Id } from "./_generated/dataModel";

// List recent sessions for a user
export const list = query({
  args: {
    userId: v.id("users"),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 10;
    const sessions = await ctx.db
      .query("sessions")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .order("desc")
      .take(limit);

    return sessions;
  },
});

// Get a session by ID
export const get = query({
  args: { id: v.id("sessions") },
  handler: async (ctx, args) => {
    return await ctx.db.get(args.id);
  },
});

// Get a session with all exercises and sets
export const getWithDetails = query({
  args: { id: v.id("sessions") },
  handler: async (ctx, args) => {
    const session = await ctx.db.get(args.id);
    if (!session) return null;

    const exercises = await ctx.db
      .query("exercises")
      .withIndex("by_session", (q) => q.eq("sessionId", args.id))
      .collect();

    const exercisesWithSets = await Promise.all(
      exercises.map(async (exercise) => {
        const sets = await ctx.db
          .query("sets")
          .withIndex("by_exercise", (q) => q.eq("exerciseId", exercise._id))
          .collect();

        return {
          ...exercise,
          sets: sets.sort((a, b) => a.order - b.order),
        };
      })
    );

    return {
      ...session,
      exercises: exercisesWithSets.sort((a, b) => a.order - b.order),
    };
  },
});

// List recent sessions with exercises and sets
export const listWithDetails = query({
  args: {
    userId: v.id("users"),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 10;
    const sessions = await ctx.db
      .query("sessions")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .order("desc")
      .take(limit);

    return await Promise.all(
      sessions.map(async (session) => {
        const exercises = await ctx.db
          .query("exercises")
          .withIndex("by_session", (q) => q.eq("sessionId", session._id))
          .collect();

        const exercisesWithSets = await Promise.all(
          exercises.map(async (exercise) => {
            const sets = await ctx.db
              .query("sets")
              .withIndex("by_exercise", (q) => q.eq("exerciseId", exercise._id))
              .collect();

            return {
              ...exercise,
              sets: sets.sort((a, b) => a.order - b.order),
            };
          })
        );

        return {
          ...session,
          exercises: exercisesWithSets.sort((a, b) => a.order - b.order),
        };
      })
    );
  },
});

// List recent completed sessions with details
export const listRecentCompleted = query({
  args: {
    userId: v.id("users"),
    limit: v.number(),
  },
  handler: async (ctx, args) => {
    const sessions = await ctx.db
      .query("sessions")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .filter((q) => q.eq(q.field("status"), "completed"))
      .order("desc")
      .take(args.limit);

    return await Promise.all(
      sessions.map(async (session) => {
        const exercises = await ctx.db
          .query("exercises")
          .withIndex("by_session", (q) => q.eq("sessionId", session._id))
          .collect();

        const exercisesWithSets = await Promise.all(
          exercises.map(async (exercise) => {
            const sets = await ctx.db
              .query("sets")
              .withIndex("by_exercise", (q) => q.eq("exerciseId", exercise._id))
              .collect();

            return {
              ...exercise,
              sets: sets.sort((a, b) => a.order - b.order),
            };
          })
        );

        return {
          ...session,
          exercises: exercisesWithSets.sort((a, b) => a.order - b.order),
        };
      })
    );
  },
});

// Create a new session
export const create = mutation({
  args: {
    userId: v.id("users"),
    status: v.union(
      v.literal("planned"),
      v.literal("active"),
      v.literal("completed")
    ),
    exercises: v.array(
      v.object({
        name: v.string(),
        muscleGroup: v.string(),
        order: v.number(),
        sets: v.array(
          v.object({
            reps: v.number(),
            weight: v.number(),
            order: v.number(),
          })
        ),
      })
    ),
  },
  handler: async (ctx, args) => {
    const now = Date.now();

    // Create the session
    const sessionId = await ctx.db.insert("sessions", {
      userId: args.userId,
      date: now,
      status: args.status,
      createdAt: now,
      updatedAt: now,
    });

    // Create exercises and sets
    for (const exerciseData of args.exercises) {
      const exerciseId = await ctx.db.insert("exercises", {
        sessionId,
        name: exerciseData.name,
        muscleGroup: exerciseData.muscleGroup,
        order: exerciseData.order,
      });

      for (const setData of exerciseData.sets) {
        await ctx.db.insert("sets", {
          exerciseId,
          reps: setData.reps,
          weight: setData.weight,
          order: setData.order,
        });
      }
    }

    return sessionId;
  },
});

// Update session status
export const updateStatus = mutation({
  args: {
    id: v.id("sessions"),
    status: v.union(
      v.literal("planned"),
      v.literal("active"),
      v.literal("completed")
    ),
  },
  handler: async (ctx, args) => {
    await ctx.db.patch(args.id, {
      status: args.status,
      updatedAt: Date.now(),
    });
  },
});
