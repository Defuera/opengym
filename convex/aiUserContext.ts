import { v } from "convex/values";
import { query } from "./_generated/server";

// ---------------------------------------------------------------------------
// Helper: fetch a session's exercises + sets
// ---------------------------------------------------------------------------
async function fetchSessionWithExercises(ctx: any, session: any) {
  const exercises = await ctx.db
    .query("exercises")
    .withIndex("by_session", (q: any) => q.eq("sessionId", session._id))
    .collect();

  const exercisesWithSets = await Promise.all(
    exercises.map(async (exercise: any) => {
      const sets = await ctx.db
        .query("sets")
        .withIndex("by_exercise", (q: any) => q.eq("exerciseId", exercise._id))
        .collect();
      return {
        ...exercise,
        sets: sets.sort((a: any, b: any) => a.order - b.order),
      };
    })
  );

  return {
    ...session,
    exercises: exercisesWithSets.sort((a: any, b: any) => a.order - b.order),
  };
}

// ---------------------------------------------------------------------------
// Public query — used by aiSessionPlanner (returns structured objects)
// ---------------------------------------------------------------------------
export const getUserContext = query({
  args: {
    userId: v.id("users"),
    sessionLimit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const sessionLimit = args.sessionLimit ?? 5;

    const user = await ctx.db.get(args.userId);
    if (!user) {
      throw new Error("User not found");
    }

    const sessions = await ctx.db
      .query("sessions")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .filter((q) => q.eq(q.field("status"), "completed"))
      .order("desc")
      .take(sessionLimit);

    const recentSessions = await Promise.all(
      sessions.map((s) => fetchSessionWithExercises(ctx, s))
    );

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
