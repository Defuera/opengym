import { v } from "convex/values";
import { query } from "./_generated/server";

// Get analytics data for a user
export const getAnalytics = query({
  args: {
    userId: v.id("users"),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    const oneWeekMs = 7 * 24 * 60 * 60 * 1000;
    // Calculate proper calendar week boundaries (Monday-based, UTC)
    const nowDate = new Date(now);
    const dayOfWeek = nowDate.getUTCDay(); // 0=Sun, 1=Mon, ...6=Sat
    const daysToMonday = dayOfWeek === 0 ? 6 : dayOfWeek - 1;
    const startOfThisWeek = Date.UTC(
      nowDate.getUTCFullYear(),
      nowDate.getUTCMonth(),
      nowDate.getUTCDate() - daysToMonday
    );
    const startOfLastWeek = startOfThisWeek - oneWeekMs;

    // Get all completed sessions
    const allSessions = await ctx.db
      .query("sessions")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .filter((q) => q.eq(q.field("status"), "completed"))
      .order("desc")
      .collect();

    // Get sessions with exercises and sets for detailed analytics
    const sessionsWithDetails = await Promise.all(
      allSessions.map(async (session) => {
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

    // Calculate session volumes
    const sessionVolumes = sessionsWithDetails.map((session) => {
      const volume = session.exercises.reduce(
        (acc, ex) =>
          acc + ex.sets.reduce((setAcc, set) => setAcc + set.reps * set.weight, 0),
        0
      );
      return {
        sessionId: session._id,
        date: session.date,
        volume,
        exerciseCount: session.exercises.length,
      };
    });

    // Filter sessions by week
    const thisWeekSessions = sessionVolumes.filter(
      (s) => s.date >= startOfThisWeek
    );
    const lastWeekSessions = sessionVolumes.filter(
      (s) => s.date >= startOfLastWeek && s.date < startOfThisWeek
    );

    // Calculate weekly stats
    const thisWeekVolume = thisWeekSessions.reduce(
      (acc, s) => acc + s.volume,
      0
    );
    const lastWeekVolume = lastWeekSessions.reduce(
      (acc, s) => acc + s.volume,
      0
    );

    // Get last 4 weeks for monthly trend (including current week)
    const fourWeeksAgo = startOfThisWeek - 3 * oneWeekMs;
    const weeklyTrend = [];
    for (let i = 0; i < 4; i++) {
      const weekStart = fourWeeksAgo + i * oneWeekMs;
      const weekEnd = weekStart + oneWeekMs;
      const weekSessions = sessionVolumes.filter(
        (s) => s.date >= weekStart && s.date < weekEnd
      );
      const weekVolume = weekSessions.reduce((acc, s) => acc + s.volume, 0);
      weeklyTrend.push({
        week: i + 1,
        volume: weekVolume,
        sessionCount: weekSessions.length,
      });
    }

    // Get last session data
    const lastSession = sessionsWithDetails[0] || null;
    let lastSessionComparison = null;

    if (lastSession) {
      const lastSessionVolume = sessionVolumes[0]?.volume || 0;
      // Find previous session with at least one matching exercise
      const lastSessionExerciseNames = new Set(
        lastSession.exercises.map((ex) => ex.name)
      );

      const previousSimilarSession = sessionsWithDetails
        .slice(1)
        .find((s) =>
          s.exercises.some((ex) => lastSessionExerciseNames.has(ex.name))
        );

      if (previousSimilarSession) {
        const previousVolume =
          sessionVolumes.find((sv) => sv.sessionId === previousSimilarSession._id)
            ?.volume || 0;
        const percentChange =
          previousVolume > 0
            ? ((lastSessionVolume - previousVolume) / previousVolume) * 100
            : 0;
        lastSessionComparison = {
          current: lastSessionVolume,
          previous: previousVolume,
          percentChange,
        };
      }
    }

    return {
      lastSession: lastSession
        ? {
            id: lastSession._id,
            date: lastSession.date,
            exercises: lastSession.exercises.map((ex) => ex.name),
            volume:
              sessionVolumes.find((sv) => sv.sessionId === lastSession._id)
                ?.volume || 0,
            comparison: lastSessionComparison,
          }
        : null,
      currentWeek: {
        sessionCount: thisWeekSessions.length,
        totalVolume: thisWeekVolume,
      },
      lastWeek: {
        sessionCount: lastWeekSessions.length,
        totalVolume: lastWeekVolume,
      },
      weeklyTrend,
    };
  },
});

// Get exercise analytics - unique exercises with their latest values and trends
export const getExerciseAnalytics = query({
  args: {
    userId: v.id("users"),
  },
  handler: async (ctx, args) => {
    // Get all completed sessions
    const sessions = await ctx.db
      .query("sessions")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .filter((q) => q.eq(q.field("status"), "completed"))
      .order("desc")
      .collect();

    // Build a map of exercises with their history
    const exerciseMap = new Map<
      string,
      {
        name: string;
        muscleGroup: string;
        history: Array<{ date: number; maxWeight: number }>;
      }
    >();

    for (const session of sessions) {
      const exercises = await ctx.db
        .query("exercises")
        .withIndex("by_session", (q) => q.eq("sessionId", session._id))
        .collect();

      for (const exercise of exercises) {
        const sets = await ctx.db
          .query("sets")
          .withIndex("by_exercise", (q) => q.eq("exerciseId", exercise._id))
          .collect();

        const maxWeight = Math.max(...sets.map((s) => s.weight), 0);

        if (!exerciseMap.has(exercise.name)) {
          exerciseMap.set(exercise.name, {
            name: exercise.name,
            muscleGroup: exercise.muscleGroup,
            history: [],
          });
        }

        exerciseMap.get(exercise.name)!.history.push({
          date: session.date,
          maxWeight,
        });
      }
    }

    // Convert to array and calculate trends
    const exerciseAnalytics = Array.from(exerciseMap.values()).map((ex) => {
      // Sort history by date descending
      ex.history.sort((a, b) => b.date - a.date);

      const lastWeight = ex.history[0]?.maxWeight || 0;
      let trend: "up" | "down" | "stable" = "stable";

      if (ex.history.length >= 2) {
        const previousWeight = ex.history[1].maxWeight;
        if (lastWeight > previousWeight) {
          trend = "up";
        } else if (lastWeight < previousWeight) {
          trend = "down";
        }
      }

      return {
        name: ex.name,
        muscleGroup: ex.muscleGroup,
        lastWeight,
        trend,
        sessionCount: ex.history.length,
      };
    });

    // Sort by most recently used
    return exerciseAnalytics.sort((a, b) => {
      const aLast = exerciseMap.get(a.name)!.history[0].date;
      const bLast = exerciseMap.get(b.name)!.history[0].date;
      return bLast - aLast;
    });
  },
});

// Get detailed analytics for a specific exercise
export const getExerciseDetail = query({
  args: {
    userId: v.id("users"),
    exerciseName: v.string(),
  },
  handler: async (ctx, args) => {
    // Get all completed sessions
    const sessions = await ctx.db
      .query("sessions")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .filter((q) => q.eq(q.field("status"), "completed"))
      .order("desc")
      .collect();

    // Collect all sessions that include this exercise
    const sessionHistory: Array<{
      sessionId: string;
      date: number;
      sets: Array<{ reps: number; weight: number }>;
    }> = [];

    let maxWeight = 0;
    let maxVolumeSession = { volume: 0, sessionId: "", date: 0 };
    let maxRepsAtHeaviestWeight = { reps: 0, weight: 0 };

    for (const session of sessions) {
      const exercises = await ctx.db
        .query("exercises")
        .withIndex("by_session", (q) => q.eq("sessionId", session._id))
        .filter((q) => q.eq(q.field("name"), args.exerciseName))
        .collect();

      // This exercise might appear multiple times in a session (rare but possible)
      for (const exercise of exercises) {
        const sets = await ctx.db
          .query("sets")
          .withIndex("by_exercise", (q) => q.eq("exerciseId", exercise._id))
          .collect();

        if (sets.length === 0) continue;

        // Store session history
        const sessionSets = sets
          .sort((a, b) => a.order - b.order)
          .map((s) => ({ reps: s.reps, weight: s.weight }));

        sessionHistory.push({
          sessionId: session._id,
          date: session.date,
          sets: sessionSets,
        });

        // Calculate records
        for (const set of sets) {
          // Max weight
          if (set.weight > maxWeight) {
            maxWeight = set.weight;
          }

          // Max reps at heaviest weight
          if (
            set.weight > maxRepsAtHeaviestWeight.weight ||
            (set.weight === maxRepsAtHeaviestWeight.weight &&
              set.reps > maxRepsAtHeaviestWeight.reps)
          ) {
            maxRepsAtHeaviestWeight = { reps: set.reps, weight: set.weight };
          }
        }

        // Session volume
        const sessionVolume = sets.reduce(
          (acc, set) => acc + set.reps * set.weight,
          0
        );
        if (sessionVolume > maxVolumeSession.volume) {
          maxVolumeSession = {
            volume: sessionVolume,
            sessionId: session._id,
            date: session.date,
          };
        }
      }
    }

    // Sort sessions by date descending (most recent first)
    sessionHistory.sort((a, b) => b.date - a.date);

    // Calculate weight progression (best weight per session)
    const weightProgression = sessionHistory.map((sh) => {
      const bestWeight = Math.max(...sh.sets.map((s) => s.weight), 0);
      return {
        date: sh.date,
        weight: bestWeight,
      };
    });

    // Calculate volume per session
    const volumePerSession = sessionHistory.map((sh) => {
      const volume = sh.sets.reduce((acc, s) => acc + s.reps * s.weight, 0);
      return {
        date: sh.date,
        volume,
      };
    });

    return {
      personalRecords: {
        maxWeight,
        maxVolumeSession: {
          volume: maxVolumeSession.volume,
          date: maxVolumeSession.date,
        },
        maxRepsAtHeaviestWeight,
      },
      weightProgression: weightProgression.reverse(), // oldest to newest for chart
      volumePerSession: volumePerSession.reverse(), // oldest to newest for chart
      sessionHistory, // Already sorted newest first
    };
  },
});
