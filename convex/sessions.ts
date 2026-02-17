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
