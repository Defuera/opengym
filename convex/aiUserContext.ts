import { v } from "convex/values";
import { query } from "./_generated/server";
import { Id } from "./_generated/dataModel";

// Get user context for AI coach: user profile, recent sessions, and memories
export const getUserContext = query({
  args: {
    userId: v.id("users"),
    sessionLimit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const sessionLimit = args.sessionLimit ?? 5;

    // Fetch user profile
    const user = await ctx.db.get(args.userId);
    if (!user) {
      throw new Error("User not found");
    }

    // Fetch recent completed sessions with details
    const sessions = await ctx.db
      .query("sessions")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .filter((q) => q.eq(q.field("status"), "completed"))
      .order("desc")
      .take(sessionLimit);

    const recentSessions = await Promise.all(
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

    // Fetch non-archived AI memories
    const aiMemories = await ctx.db
      .query("aiMemories")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .filter((q) => q.eq(q.field("archivedAt"), undefined))
      .collect();

    return {
      user,
      recentSessions,
      aiMemories,
    };
  },
});
