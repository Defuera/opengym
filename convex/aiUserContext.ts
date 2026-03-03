import { v } from "convex/values";
import { internalQuery, query } from "./_generated/server";
import { Id } from "./_generated/dataModel";

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
// Rich internal query used by AI actions
// ---------------------------------------------------------------------------
export const buildAIContext = internalQuery({
  args: {
    userId: v.id("users"),
    sessionLimit: v.optional(v.number()),
    currentSessionId: v.optional(v.id("sessions")),
  },
  handler: async (ctx, args) => {
    const limit = args.sessionLimit ?? 10;

    // 1. User profile
    const user = await ctx.db.get(args.userId);

    // 2. Recent completed sessions with full exercise+set details
    const rawSessions = await ctx.db
      .query("sessions")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .filter((q) => q.eq(q.field("status"), "completed"))
      .order("desc")
      .take(limit);

    const recentSessions = await Promise.all(
      rawSessions.map((s) => fetchSessionWithExercises(ctx, s))
    );

    // 3. Current session details (if reviewing a specific session)
    let currentSession: any = null;
    if (args.currentSessionId) {
      const raw = await ctx.db.get(args.currentSessionId);
      if (raw) {
        currentSession = await fetchSessionWithExercises(ctx, raw);
      }
    }

    // 4. Per-exercise history — group by exercise name, last 10 per exercise
    // Collect from recentSessions (plus currentSession if it's not already in there)
    const allSessionsForHistory = currentSession
      ? [
          currentSession,
          ...recentSessions.filter(
            (s: any) => s._id !== args.currentSessionId
          ),
        ]
      : recentSessions;

    const exerciseHistory: Record<
      string,
      Array<{
        date: number;
        sets: Array<{ reps: number; weight: number; order: number }>;
        topSet: { reps: number; weight: number };
        totalVolume: number;
      }>
    > = {};

    for (const session of allSessionsForHistory) {
      for (const exercise of (session as any).exercises ?? []) {
        const name: string = exercise.name;
        if (!exerciseHistory[name]) {
          exerciseHistory[name] = [];
        }
        if (exerciseHistory[name].length >= 10) continue; // already have 10

        const sets: Array<{ reps: number; weight: number; order: number }> =
          exercise.sets ?? [];
        const totalVolume = sets.reduce(
          (sum, s) => sum + s.reps * s.weight,
          0
        );
        const topSet = sets.reduce(
          (best, s) =>
            s.weight > best.weight || (s.weight === best.weight && s.reps > best.reps)
              ? s
              : best,
          { reps: 0, weight: 0, order: 0 }
        );

        exerciseHistory[name].push({
          date: (session as any).date,
          sets,
          topSet: { reps: topSet.reps, weight: topSet.weight },
          totalVolume,
        });
      }
    }

    // 5. Recovery context
    const lastSession = recentSessions[0] as any | undefined;
    const daysSinceLastSession = lastSession
      ? Math.floor((Date.now() - lastSession.date) / (1000 * 60 * 60 * 24))
      : null;
    const oneWeekAgo = Date.now() - 7 * 24 * 60 * 60 * 1000;
    const sessionsThisWeek = recentSessions.filter(
      (s: any) => s.date >= oneWeekAgo
    ).length;

    // 6. AI memories (non-archived)
    const aiMemories = await ctx.db
      .query("aiMemories")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .filter((q) => q.eq(q.field("archivedAt"), undefined))
      .collect();

    return {
      user,
      recentSessions,
      currentSession,
      exerciseHistory,
      recoveryContext: { daysSinceLastSession, sessionsThisWeek },
      aiMemories,
    };
  },
});

// ---------------------------------------------------------------------------
// Public query — kept for backward compatibility (aiSessionPlanner uses this)
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
