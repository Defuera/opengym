import { v } from "convex/values";
import { query, mutation } from "./_generated/server";
import { Id } from "./_generated/dataModel";

/**
 * AI Coach Tools – callable from Next.js API route via ConvexHttpClient.
 * These are standard (public) queries/mutations so they can be invoked
 * without a Convex auth token from server-side code.
 */

// ---------------------------------------------------------------------------
// READ TOOLS
// ---------------------------------------------------------------------------

/** Get recent workout sessions with their exercise names */
export const getRecentSessions = query({
  args: {
    userId: v.string(),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 10;
    const userId = args.userId as Id<"users">;

    const sessions = await ctx.db
      .query("sessions")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .order("desc")
      .take(limit);

    return await Promise.all(
      sessions.map(async (session) => {
        const exercises = await ctx.db
          .query("exercises")
          .withIndex("by_session", (q) => q.eq("sessionId", session._id))
          .collect();
        return {
          sessionId: session._id as string,
          name: session.name ?? null,
          date: session.date,
          status: session.status,
          exerciseNames: exercises.map((e) => e.name),
        };
      })
    );
  },
});

/** Get full detail of a session including all sets */
export const getSessionDetail = query({
  args: {
    userId: v.string(),
    sessionId: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionId = args.sessionId as Id<"sessions">;
    const session = await ctx.db.get(sessionId);
    if (!session) return null;

    const exercises = await ctx.db
      .query("exercises")
      .withIndex("by_session", (q) => q.eq("sessionId", sessionId))
      .collect();

    const exercisesWithSets = await Promise.all(
      exercises.map(async (exercise) => {
        const sets = await ctx.db
          .query("sets")
          .withIndex("by_exercise", (q) => q.eq("exerciseId", exercise._id))
          .collect();
        return {
          exerciseId: exercise._id as string,
          name: exercise.name,
          muscleGroup: exercise.muscleGroup,
          sets: sets
            .sort((a, b) => a.order - b.order)
            .map((s) => ({
              setId: s._id as string,
              reps: s.reps,
              weight: s.weight,
              status: s.status,
            })),
        };
      })
    );

    return {
      sessionId: session._id as string,
      name: session.name ?? null,
      date: session.date,
      status: session.status,
      exercises: exercisesWithSets.sort((a, b) => {
        const ea = exercises.find((e) => e._id === a.exerciseId);
        const eb = exercises.find((e) => e._id === b.exerciseId);
        return (ea?.order ?? 0) - (eb?.order ?? 0);
      }),
    };
  },
});

/** Get history of a specific exercise by name across all sessions */
export const getExerciseHistory = query({
  args: {
    userId: v.string(),
    exerciseName: v.string(),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 20;
    const userId = args.userId as Id<"users">;

    // Get all sessions for this user
    const sessions = await ctx.db
      .query("sessions")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .order("desc")
      .collect();

    const results: Array<{
      sessionId: string;
      sessionDate: number;
      sessionName: string | null;
      sets: Array<{ reps: number; weight: number; status?: string }>;
    }> = [];

    for (const session of sessions) {
      if (results.length >= limit) break;

      const exercises = await ctx.db
        .query("exercises")
        .withIndex("by_session", (q) => q.eq("sessionId", session._id))
        .collect();

      const match = exercises.find(
        (e) => e.name.toLowerCase() === args.exerciseName.toLowerCase()
      );

      if (match) {
        const sets = await ctx.db
          .query("sets")
          .withIndex("by_exercise", (q) => q.eq("exerciseId", match._id))
          .collect();

        results.push({
          sessionId: session._id as string,
          sessionDate: session.date,
          sessionName: session.name ?? null,
          sets: sets
            .sort((a, b) => a.order - b.order)
            .map((s) => ({ reps: s.reps, weight: s.weight, status: s.status })),
        });
      }
    }

    return results;
  },
});

/** Get unique exercises (catalog) from all of the user's sessions */
export const getExercises = query({
  args: {
    userId: v.string(),
  },
  handler: async (ctx, args) => {
    const userId = args.userId as Id<"users">;

    const sessions = await ctx.db
      .query("sessions")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .collect();

    const seen = new Map<string, { name: string; muscleGroup: string; exerciseId: string }>();

    for (const session of sessions) {
      const exercises = await ctx.db
        .query("exercises")
        .withIndex("by_session", (q) => q.eq("sessionId", session._id))
        .collect();
      for (const e of exercises) {
        const key = e.name.toLowerCase();
        if (!seen.has(key)) {
          seen.set(key, {
            name: e.name,
            muscleGroup: e.muscleGroup,
            exerciseId: e._id as string,
          });
        }
      }
    }

    return Array.from(seen.values());
  },
});

// ---------------------------------------------------------------------------
// WRITE TOOLS
// ---------------------------------------------------------------------------

/** Create a new workout session, return sessionId */
export const createSession = mutation({
  args: {
    userId: v.string(),
    name: v.string(),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    const sessionId = await ctx.db.insert("sessions", {
      userId: args.userId as Id<"users">,
      name: args.name,
      date: now,
      status: "active",
      createdAt: now,
      updatedAt: now,
    });
    return sessionId as string;
  },
});

/** Log a set for an exercise in a session */
export const logSet = mutation({
  args: {
    userId: v.string(),
    sessionId: v.string(),
    exerciseId: v.string(),
    reps: v.number(),
    weight: v.number(),
  },
  handler: async (ctx, args) => {
    const exerciseId = args.exerciseId as Id<"exercises">;

    // Get existing sets for ordering
    const existingSets = await ctx.db
      .query("sets")
      .withIndex("by_exercise", (q) => q.eq("exerciseId", exerciseId))
      .collect();

    const setId = await ctx.db.insert("sets", {
      exerciseId,
      reps: args.reps,
      weight: args.weight,
      order: existingSets.length,
      status: "complete",
    });

    // Update session updatedAt
    const sessionId = args.sessionId as Id<"sessions">;
    await ctx.db.patch(sessionId, { updatedAt: Date.now() });

    return setId as string;
  },
});

/** Mark a workout session as complete */
export const completeSession = mutation({
  args: {
    userId: v.string(),
    sessionId: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionId = args.sessionId as Id<"sessions">;
    await ctx.db.patch(sessionId, {
      status: "completed",
      updatedAt: Date.now(),
    });
    return true;
  },
});

/** Add an exercise to an existing session */
export const addExercise = mutation({
  args: {
    userId: v.string(),
    sessionId: v.string(),
    name: v.string(),
    muscleGroup: v.string(),
  },
  handler: async (ctx, args) => {
    const sessionId = args.sessionId as Id<"sessions">;

    const existingExercises = await ctx.db
      .query("exercises")
      .withIndex("by_session", (q) => q.eq("sessionId", sessionId))
      .collect();

    const exerciseId = await ctx.db.insert("exercises", {
      sessionId,
      name: args.name,
      muscleGroup: args.muscleGroup,
      order: existingExercises.length,
    });

    return exerciseId as string;
  },
});
