import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { internal } from "./_generated/api";
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
    date: v.optional(v.number()),
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
      date: args.date ?? now,
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
          status: "todo",
        });
      }
    }

    return sessionId;
  },
});

// Delete a session and all its exercises and sets
export const deleteSession = mutation({
  args: { id: v.id("sessions") },
  handler: async (ctx, args) => {
    const exercises = await ctx.db
      .query("exercises")
      .withIndex("by_session", (q) => q.eq("sessionId", args.id))
      .collect();
    for (const exercise of exercises) {
      const sets = await ctx.db
        .query("sets")
        .withIndex("by_exercise", (q) => q.eq("exerciseId", exercise._id))
        .collect();
      for (const set of sets) await ctx.db.delete(set._id);
      await ctx.db.delete(exercise._id);
    }
    await ctx.db.delete(args.id);
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

// Get sessions grouped by ISO week with their AI summaries
export const getWeeklySessionsWithSummaries = query({
  args: {
    userId: v.id("users"),
    weeksBack: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const weeksBack = args.weeksBack ?? 8;
    const now = Date.now();

    // Compute the start of the current ISO week (Monday)
    const nowDate = new Date(now);
    const dayOfWeek = nowDate.getUTCDay(); // 0=Sun
    const daysToMonday = dayOfWeek === 0 ? 6 : dayOfWeek - 1;
    const startOfThisWeek = Date.UTC(
      nowDate.getUTCFullYear(),
      nowDate.getUTCMonth(),
      nowDate.getUTCDate() - daysToMonday
    );

    const oneWeekMs = 7 * 24 * 60 * 60 * 1000;
    const rangeStart = startOfThisWeek - (weeksBack - 1) * oneWeekMs;

    // Fetch all completed sessions in range
    const sessions = await ctx.db
      .query("sessions")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .filter((q) =>
        q.and(
          q.eq(q.field("status"), "completed"),
          q.gte(q.field("date"), rangeStart)
        )
      )
      .order("desc")
      .collect();

    // Fetch exercises for each session
    const sessionsWithExercises = await Promise.all(
      sessions.map(async (session) => {
        const exercises = await ctx.db
          .query("exercises")
          .withIndex("by_session", (q) => q.eq("sessionId", session._id))
          .collect();
        return { ...session, exercises };
      })
    );

    // Fetch summaries for all sessions in one pass
    const summaryMap = new Map<string, any>();
    for (const session of sessions) {
      const summary = await ctx.db
        .query("sessionSummaries")
        .withIndex("by_session", (q) => q.eq("sessionId", session._id))
        .first();
      if (summary) {
        summaryMap.set(session._id, summary);
      }
    }

    // Build week buckets from newest to oldest
    const weeks: Array<{
      weekStart: number;
      weekEnd: number;
      sessions: Array<{
        sessionId: string;
        date: number;
        exerciseNames: string[];
        summary?: {
          trend: string;
          score: number;
          headline: string;
          highlights: string[];
          muscleGroups: string[];
          generatedAt: number;
        };
      }>;
    }> = [];

    for (let i = 0; i < weeksBack; i++) {
      const weekStart = startOfThisWeek - i * oneWeekMs;
      const weekEnd = weekStart + oneWeekMs - 1;

      const weekSessions = sessionsWithExercises
        .filter((s) => s.date >= weekStart && s.date <= weekEnd)
        .sort((a, b) => a.date - b.date)
        .map((s) => ({
          sessionId: s._id as string,
          date: s.date,
          exerciseNames: (s.exercises ?? []).map((e: any) => e.name),
          summary: summaryMap.get(s._id) ?? undefined,
        }));

      weeks.push({ weekStart, weekEnd, sessions: weekSessions });
    }

    return weeks;
  },
});
