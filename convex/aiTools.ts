import { v } from "convex/values";
import { query, mutation } from "./_generated/server";
import { Id } from "./_generated/dataModel";

/**
 * AI Coach Tools – callable from Next.js API route via ConvexHttpClient.
 * These are standard (public) queries/mutations so they can be invoked
 * without a Convex auth token from server-side code.
 *
 * SECURITY NOTE: This project does not yet have a server-side auth system
 * (e.g. Clerk). The `userId` arg is currently supplied by the caller and is
 * NOT cryptographically verified on the Convex side.
 *
 * TODO: When Clerk (or another auth provider) is integrated:
 *   1. Remove `userId` from all public function args.
 *   2. Derive userId server-side: `const identity = await ctx.auth.getUserIdentity();`
 *      then use `identity.subject` or `identity.tokenIdentifier` as the userId.
 *   3. Throw if identity is null (unauthenticated call).
 *
 * In the meantime, ownership is enforced inside write operations by fetching
 * the parent record and verifying its `userId` matches the supplied arg before
 * making any changes. Read-only queries are scoped by the supplied userId, so
 * data returned is always that user's own data.
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
    // TODO: replace args.userId with server-verified identity when auth is added.
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
    // TODO: replace args.userId with server-verified identity when auth is added.
    const sessionId = args.sessionId as Id<"sessions">;
    const session = await ctx.db.get(sessionId);
    if (!session) return null;
    // Ownership check: ensure the session belongs to the supplied userId.
    if (session.userId !== (args.userId as Id<"users">)) return null;

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

/**
 * Get history of a specific exercise by name across all sessions.
 *
 * Uses the exercises.by_user index to fetch exercises in O(1) rather than
 * issuing one query per session (N+1). Falls back to session-by-session scan
 * for exercises that pre-date the userId field being added to the schema.
 */
export const getExerciseHistory = query({
  args: {
    userId: v.string(),
    exerciseName: v.string(),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    // TODO: replace args.userId with server-verified identity when auth is added.
    const limit = args.limit ?? 20;
    const userId = args.userId as Id<"users">;
    const nameLower = args.exerciseName.toLowerCase();

    // Efficient path: query exercises directly by userId using the by_user index,
    // then filter by name in application code (Convex indexes are equality-only).
    const allUserExercises = await ctx.db
      .query("exercises")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .collect();

    const matchingExercises = allUserExercises.filter(
      (e) => e.name.toLowerCase() === nameLower
    );

    // Track IDs from primary path to avoid duplicates in fallback.
    const seenExerciseIds = new Set(matchingExercises.map((e) => e._id as string));

    // Fallback: include legacy exercises that pre-date the userId field.
    // Fetch sessions for this user, then exercises by session where userId is absent.
    const userSessions = await ctx.db
      .query("sessions")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .collect();

    const legacyMatches = (
      await Promise.all(
        userSessions.map((session) =>
          ctx.db
            .query("exercises")
            .withIndex("by_session", (q) => q.eq("sessionId", session._id))
            .collect()
        )
      )
    )
      .flat()
      .filter(
        (e) =>
          !e.userId &&
          e.name.toLowerCase() === nameLower &&
          !seenExerciseIds.has(e._id as string)
      );

    const combined = [...matchingExercises, ...legacyMatches];

    // Fetch sessions and sets for matching exercises in parallel, sort by date desc.
    const results = (
      await Promise.all(
        combined.map(async (exercise) => {
          const [session, sets] = await Promise.all([
            ctx.db.get(exercise.sessionId),
            ctx.db
              .query("sets")
              .withIndex("by_exercise", (q) => q.eq("exerciseId", exercise._id))
              .collect(),
          ]);
          if (!session) return null;
          return {
            sessionId: session._id as string,
            sessionDate: session.date,
            sessionName: session.name ?? null,
            sets: sets
              .sort((a, b) => a.order - b.order)
              .map((s) => ({ reps: s.reps, weight: s.weight, status: s.status })),
          };
        })
      )
    ).filter((r): r is NonNullable<typeof r> => r !== null);

    return results
      .sort((a, b) => b.sessionDate - a.sessionDate)
      .slice(0, limit);
  },
});

/**
 * Get unique exercises (catalog) from all of the user's sessions.
 *
 * Uses the exercises.by_user index to fetch exercises in O(1) rather than
 * issuing one query per session (N+1).
 */
export const getExercises = query({
  args: {
    userId: v.string(),
  },
  handler: async (ctx, args) => {
    // TODO: replace args.userId with server-verified identity when auth is added.
    const userId = args.userId as Id<"users">;

    // Efficient path: query exercises directly by userId (avoids N+1 through sessions).
    const allUserExercises = await ctx.db
      .query("exercises")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .collect();

    const seen = new Map<string, { name: string; muscleGroup: string; exerciseId: string }>();
    for (const e of allUserExercises) {
      const key = e.name.toLowerCase();
      if (!seen.has(key)) {
        seen.set(key, { name: e.name, muscleGroup: e.muscleGroup, exerciseId: e._id as string });
      }
    }

    // Fallback: include legacy exercises that pre-date the userId field.
    const userSessions = await ctx.db
      .query("sessions")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .collect();

    const legacyExercises = (
      await Promise.all(
        userSessions.map((session) =>
          ctx.db
            .query("exercises")
            .withIndex("by_session", (q) => q.eq("sessionId", session._id))
            .collect()
        )
      )
    )
      .flat()
      .filter((e) => !e.userId);

    for (const e of legacyExercises) {
      const key = e.name.toLowerCase();
      if (!seen.has(key)) {
        seen.set(key, { name: e.name, muscleGroup: e.muscleGroup, exerciseId: e._id as string });
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
    // TODO: replace args.userId with server-verified identity when auth is added.
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
    // TODO: replace args.userId with server-verified identity when auth is added.
    const sessionId = args.sessionId as Id<"sessions">;
    // Ownership check: verify session belongs to the supplied userId.
    const session = await ctx.db.get(sessionId);
    if (!session || session.userId !== (args.userId as Id<"users">)) {
      throw new Error("Session not found or access denied");
    }

    const exerciseId = args.exerciseId as Id<"exercises">;
    const exercise = await ctx.db.get(exerciseId);
    if (!exercise || exercise.sessionId !== sessionId) {
      throw new Error("Exercise not found or does not belong to this session");
    }

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
    // TODO: replace args.userId with server-verified identity when auth is added.
    const sessionId = args.sessionId as Id<"sessions">;
    // Ownership check: verify session belongs to the supplied userId.
    const session = await ctx.db.get(sessionId);
    if (!session || session.userId !== (args.userId as Id<"users">)) {
      throw new Error("Session not found or access denied");
    }
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
    // TODO: replace args.userId with server-verified identity when auth is added.
    const sessionId = args.sessionId as Id<"sessions">;
    const userId = args.userId as Id<"users">;
    // Ownership check: verify session belongs to the supplied userId.
    const session = await ctx.db.get(sessionId);
    if (!session || session.userId !== userId) {
      throw new Error("Session not found or access denied");
    }

    const existingExercises = await ctx.db
      .query("exercises")
      .withIndex("by_session", (q) => q.eq("sessionId", sessionId))
      .collect();

    const exerciseId = await ctx.db.insert("exercises", {
      sessionId,
      // Store userId so exercises can be queried directly by user (avoids N+1).
      userId,
      name: args.name,
      muscleGroup: args.muscleGroup,
      order: existingExercises.length,
    });

    return exerciseId as string;
  },
});
