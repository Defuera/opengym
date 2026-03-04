import { v } from "convex/values";
import { internalQuery, internalMutation } from "./_generated/server";
import { Id } from "./_generated/dataModel";

/**
 * AI Coach Tools — internal queries/mutations callable only from other
 * Convex functions (actions, scheduled functions). Not exposed to clients.
 */

/** Fetch legacy exercises (missing userId field) via session scan */
async function getLegacyExercises(ctx: any, userId: Id<"users">) {
  const userSessions = await ctx.db
    .query("sessions")
    .withIndex("by_user", (q: any) => q.eq("userId", userId))
    .collect();
  return (
    await Promise.all(
      userSessions.map((session: any) =>
        ctx.db
          .query("exercises")
          .withIndex("by_session", (q: any) => q.eq("sessionId", session._id))
          .collect()
      )
    )
  )
    .flat()
    .filter((e: any) => !e.userId);
}

/** Get workout sessions with optional status filter */
export const getSessions = internalQuery({
  args: {
    userId: v.id("users"),
    status: v.optional(v.string()),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 10;
    let sessions = await ctx.db
      .query("sessions")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .order("desc")
      .collect();

    if (args.status) {
      sessions = sessions.filter((s) => s.status === args.status);
    }
    sessions = sessions.slice(0, limit);

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
export const getSessionDetail = internalQuery({
  args: {
    userId: v.id("users"),
    sessionId: v.id("sessions"),
  },
  handler: async (ctx, args) => {
    const session = await ctx.db.get(args.sessionId);
    if (!session || session.userId !== args.userId) return null;

    const exercises = await ctx.db
      .query("exercises")
      .withIndex("by_session", (q) => q.eq("sessionId", args.sessionId))
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
        const ea = exercises.find((e) => e._id === (a.exerciseId as Id<"exercises">));
        const eb = exercises.find((e) => e._id === (b.exerciseId as Id<"exercises">));
        return (ea?.order ?? 0) - (eb?.order ?? 0);
      }),
    };
  },
});

/**
 * Get history of a specific exercise by name across all sessions.
 * Uses the exercises.by_user index; falls back to session scan for legacy data.
 */
export const getExerciseHistory = internalQuery({
  args: {
    userId: v.id("users"),
    exerciseName: v.string(),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 20;
    const nameLower = args.exerciseName.toLowerCase();

    const allUserExercises = await ctx.db
      .query("exercises")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .collect();

    const matchingExercises = allUserExercises.filter(
      (e) => e.name.toLowerCase() === nameLower
    );

    const seenExerciseIds = new Set(matchingExercises.map((e) => e._id as string));
    const legacyAll = await getLegacyExercises(ctx, args.userId);
    const legacyMatches = legacyAll.filter(
      (e: any) =>
        e.name.toLowerCase() === nameLower && !seenExerciseIds.has(e._id as string)
    );

    const combined = [...matchingExercises, ...legacyMatches];

    const results = (
      await Promise.all(
        combined.map(async (exercise) => {
          const [sessionDoc, sets] = await Promise.all([
            ctx.db.get(exercise.sessionId),
            ctx.db
              .query("sets")
              .withIndex("by_exercise", (q) => q.eq("exerciseId", exercise._id))
              .collect(),
          ]);
          if (!sessionDoc) return null;
          const s = sessionDoc as { _id: any; date: number; name?: string };
          return {
            sessionId: s._id as string,
            sessionDate: s.date,
            sessionName: s.name ?? null,
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

/** Get unique exercises (catalog) from all of the user's sessions */
export const getExercises = internalQuery({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const allUserExercises = await ctx.db
      .query("exercises")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .collect();

    const seen = new Map<string, { name: string; muscleGroup: string; exerciseId: string }>();
    for (const e of allUserExercises) {
      const key = e.name.toLowerCase();
      if (!seen.has(key)) {
        seen.set(key, { name: e.name, muscleGroup: e.muscleGroup, exerciseId: e._id as string });
      }
    }

    const legacyExercises = await getLegacyExercises(ctx, args.userId);
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

/** Create a new workout session */
export const createSession = internalMutation({
  args: {
    userId: v.id("users"),
    name: v.string(),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    const sessionId = await ctx.db.insert("sessions", {
      userId: args.userId,
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
export const logSet = internalMutation({
  args: {
    userId: v.id("users"),
    sessionId: v.id("sessions"),
    exerciseId: v.id("exercises"),
    reps: v.number(),
    weight: v.number(),
  },
  handler: async (ctx, args) => {
    const session = await ctx.db.get(args.sessionId);
    if (!session || session.userId !== args.userId) {
      throw new Error("Session not found or access denied");
    }

    const exercise = await ctx.db.get(args.exerciseId);
    if (!exercise || exercise.sessionId !== args.sessionId) {
      throw new Error("Exercise not found or does not belong to this session");
    }

    const existingSets = await ctx.db
      .query("sets")
      .withIndex("by_exercise", (q) => q.eq("exerciseId", args.exerciseId))
      .collect();

    const setId = await ctx.db.insert("sets", {
      exerciseId: args.exerciseId,
      reps: args.reps,
      weight: args.weight,
      order: existingSets.length,
      status: "complete",
    });

    await ctx.db.patch(args.sessionId, { updatedAt: Date.now() });
    return setId as string;
  },
});

/** Mark a workout session as complete */
export const completeSession = internalMutation({
  args: {
    userId: v.id("users"),
    sessionId: v.id("sessions"),
  },
  handler: async (ctx, args) => {
    const session = await ctx.db.get(args.sessionId);
    if (!session || session.userId !== args.userId) {
      throw new Error("Session not found or access denied");
    }
    await ctx.db.patch(args.sessionId, {
      status: "completed",
      updatedAt: Date.now(),
    });
    return true;
  },
});

/** Add an exercise to an existing session */
export const addExercise = internalMutation({
  args: {
    userId: v.id("users"),
    sessionId: v.id("sessions"),
    name: v.string(),
    muscleGroup: v.string(),
  },
  handler: async (ctx, args) => {
    const session = await ctx.db.get(args.sessionId);
    if (!session || session.userId !== args.userId) {
      throw new Error("Session not found or access denied");
    }

    const existingExercises = await ctx.db
      .query("exercises")
      .withIndex("by_session", (q) => q.eq("sessionId", args.sessionId))
      .collect();

    const exerciseId = await ctx.db.insert("exercises", {
      sessionId: args.sessionId,
      userId: args.userId,
      name: args.name,
      muscleGroup: args.muscleGroup,
      order: existingExercises.length,
    });

    return exerciseId as string;
  },
});

/** Rename a session */
export const renameSession = internalMutation({
  args: {
    userId: v.id("users"),
    sessionId: v.id("sessions"),
    name: v.string(),
  },
  handler: async (ctx, args) => {
    const session = await ctx.db.get(args.sessionId);
    if (!session || session.userId !== args.userId) {
      throw new Error("Session not found or access denied");
    }
    await ctx.db.patch(args.sessionId, { name: args.name, updatedAt: Date.now() });
    return true;
  },
});

/** Delete a session and all its exercises and sets */
export const deleteSession = internalMutation({
  args: {
    userId: v.id("users"),
    sessionId: v.id("sessions"),
  },
  handler: async (ctx, args) => {
    const session = await ctx.db.get(args.sessionId);
    if (!session || session.userId !== args.userId) {
      throw new Error("Session not found or access denied");
    }

    const exercises = await ctx.db
      .query("exercises")
      .withIndex("by_session", (q) => q.eq("sessionId", args.sessionId))
      .collect();

    for (const exercise of exercises) {
      const sets = await ctx.db
        .query("sets")
        .withIndex("by_exercise", (q) => q.eq("exerciseId", exercise._id))
        .collect();
      for (const set of sets) {
        await ctx.db.delete(set._id);
      }
      await ctx.db.delete(exercise._id);
    }

    await ctx.db.delete(args.sessionId);
    return true;
  },
});

/** Delete an exercise and all its sets */
export const deleteExercise = internalMutation({
  args: {
    userId: v.id("users"),
    exerciseId: v.id("exercises"),
  },
  handler: async (ctx, args) => {
    const exercise = await ctx.db.get(args.exerciseId);
    if (!exercise) throw new Error("Exercise not found");

    const session = await ctx.db.get(exercise.sessionId);
    if (!session || session.userId !== args.userId) {
      throw new Error("Access denied");
    }

    const sets = await ctx.db
      .query("sets")
      .withIndex("by_exercise", (q) => q.eq("exerciseId", args.exerciseId))
      .collect();
    for (const set of sets) {
      await ctx.db.delete(set._id);
    }

    await ctx.db.delete(args.exerciseId);
    return true;
  },
});

/** Update a set's reps and/or weight */
export const updateSet = internalMutation({
  args: {
    userId: v.id("users"),
    setId: v.id("sets"),
    reps: v.optional(v.number()),
    weight: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const set = await ctx.db.get(args.setId);
    if (!set) throw new Error("Set not found");

    const exercise = await ctx.db.get(set.exerciseId);
    if (!exercise) throw new Error("Exercise not found");

    const session = await ctx.db.get(exercise.sessionId);
    if (!session || session.userId !== args.userId) {
      throw new Error("Access denied");
    }

    const patch: Record<string, number> = {};
    if (args.reps !== undefined) patch.reps = args.reps;
    if (args.weight !== undefined) patch.weight = args.weight;
    if (Object.keys(patch).length === 0) throw new Error("Nothing to update");

    await ctx.db.patch(args.setId, patch);
    return true;
  },
});

/** Delete a set */
export const deleteSet = internalMutation({
  args: {
    userId: v.id("users"),
    setId: v.id("sets"),
  },
  handler: async (ctx, args) => {
    const set = await ctx.db.get(args.setId);
    if (!set) throw new Error("Set not found");

    const exercise = await ctx.db.get(set.exerciseId);
    if (!exercise) throw new Error("Exercise not found");

    const session = await ctx.db.get(exercise.sessionId);
    if (!session || session.userId !== args.userId) {
      throw new Error("Access denied");
    }

    await ctx.db.delete(args.setId);
    return true;
  },
});

// ---------------------------------------------------------------------------
// MEMORY TOOLS
// ---------------------------------------------------------------------------

/** List non-archived memories for a user */
export const listMemories = internalQuery({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const memories = await ctx.db
      .query("aiMemories")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .filter((q) => q.eq(q.field("archivedAt"), undefined))
      .collect();

    return memories.map((m) => ({
      memoryId: m._id as string,
      type: m.type,
      key: m.key,
      value: m.value,
      createdAt: m.createdAt,
    }));
  },
});

/** Save (upsert) a memory */
export const saveMemory = internalMutation({
  args: {
    userId: v.id("users"),
    type: v.union(
      v.literal("preference"),
      v.literal("constraint"),
      v.literal("injury"),
      v.literal("meta")
    ),
    key: v.string(),
    value: v.string(),
  },
  handler: async (ctx, args) => {
    const now = Date.now();

    const existing = await ctx.db
      .query("aiMemories")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .filter((q) =>
        q.and(
          q.eq(q.field("key"), args.key),
          q.eq(q.field("archivedAt"), undefined)
        )
      )
      .first();

    if (existing) {
      await ctx.db.patch(existing._id, {
        type: args.type,
        value: args.value,
        source: "ai" as const,
        updatedAt: now,
      });
      return existing._id as string;
    }

    const id = await ctx.db.insert("aiMemories", {
      userId: args.userId,
      type: args.type,
      key: args.key,
      value: args.value,
      source: "ai" as const,
      createdAt: now,
      updatedAt: now,
    });
    return id as string;
  },
});

/** Archive (soft-delete) a memory */
export const deleteMemory = internalMutation({
  args: {
    userId: v.id("users"),
    memoryId: v.id("aiMemories"),
  },
  handler: async (ctx, args) => {
    const memory = await ctx.db.get(args.memoryId);
    if (!memory || memory.userId !== args.userId) {
      throw new Error("Memory not found or access denied");
    }
    const now = Date.now();
    await ctx.db.patch(args.memoryId, { archivedAt: now, updatedAt: now });
    return true;
  },
});
