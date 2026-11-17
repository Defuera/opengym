import { internalQuery } from "./_generated/server";
import { v } from "convex/values";

// ---------------------------------------------------------------------------
// Pure formatting helpers
// ---------------------------------------------------------------------------

function formatDate(timestamp: number): string {
  const d = new Date(timestamp);
  const months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ];
  return `${months[d.getMonth()]} ${d.getDate()}`;
}

type SessionWithExercises = {
  _id: string;
  date: number;
  status: string;
  exercises: Array<{
    name: string;
    order: number;
    sets: Array<{ reps: number; weight: number; order: number }>;
  }>;
};

export function formatWorkoutCSV(
  sessions: SessionWithExercises[],
  currentSessionId?: string
): string {
  const rows: string[] = ["date,exercise,sets"];

  for (const session of sessions) {
    const isCurrent = session._id === currentSessionId;
    const sorted = [...(session.exercises ?? [])].sort(
      (a, b) => a.order - b.order
    );

    for (const exercise of sorted) {
      const sortedSets = [...(exercise.sets ?? [])].sort(
        (a, b) => a.order - b.order
      );
      const setsStr = sortedSets
        .map((s) => (s.weight > 0 ? `${s.reps}x${s.weight}` : `${s.reps}`))
        .join(" → ");

      const date = isCurrent ? "TODAY" : formatDate(session.date);
      rows.push(`${date},${exercise.name},${setsStr}`);
    }
  }

  return rows.join("\n");
}

export function formatRecovery(completedSessions: Array<{ date: number }>): string {
  if (completedSessions.length === 0) return "";
  const now = Date.now();
  const daysSinceLast = Math.floor(
    (now - completedSessions[0].date) / (1000 * 60 * 60 * 24)
  );
  const oneWeekAgo = now - 7 * 24 * 60 * 60 * 1000;
  const sessionsThisWeek = completedSessions.filter(
    (s) => s.date >= oneWeekAgo
  ).length;
  return `${daysSinceLast}d since last session, ${sessionsThisWeek} sessions this week`;
}

export function formatMemories(
  memories: Array<{ type: string; key: string; value: string }>
): string {
  if (memories.length === 0) return "";
  return memories.map((m) => `${m.type}: ${m.key} = ${m.value}`).join("; ");
}

export function formatUserProfile(user: {
  name: string;
  unit?: string;
}): string {
  return `USER: ${user.name}, units: ${user.unit ?? "metric"}`;
}

// ---------------------------------------------------------------------------
// Centralized context builder
// ---------------------------------------------------------------------------
export const buildContext = internalQuery({
  args: {
    userId: v.id("users"),
    sessionLimit: v.optional(v.number()),
    currentSessionId: v.optional(v.id("sessions")),
  },
  handler: async (ctx, args) => {
    const user = await ctx.db.get(args.userId);
    if (!user) return "";

    const limit = args.sessionLimit ?? 5;

    // Recent sessions (completed, desc)
    const sessions = await ctx.db
      .query("sessions")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .filter((q) => q.eq(q.field("status"), "completed"))
      .order("desc")
      .take(limit);

    // Fetch exercises + sets for each session
    const sessionsWithExercises: SessionWithExercises[] = await Promise.all(
      sessions.map(async (session) => {
        const exercises = await ctx.db
          .query("exercises")
          .withIndex("by_session", (q) => q.eq("sessionId", session._id))
          .collect();

        const exercisesWithSets = await Promise.all(
          exercises.map(async (exercise) => {
            const sets = await ctx.db
              .query("sets")
              .withIndex("by_exercise", (q) =>
                q.eq("exerciseId", exercise._id)
              )
              .collect();
            return {
              name: exercise.name,
              order: exercise.order,
              sets: sets
                .sort((a, b) => a.order - b.order)
                .map((s) => ({ reps: s.reps, weight: s.weight, order: s.order })),
            };
          })
        );

        return {
          _id: session._id as string,
          date: session.date,
          status: session.status,
          exercises: exercisesWithSets.sort((a, b) => a.order - b.order),
        };
      })
    );

    // Current session (if specified and not already in list)
    let currentSessionData: SessionWithExercises | null = null;
    if (args.currentSessionId) {
      const existing = sessionsWithExercises.find(
        (s) => s._id === args.currentSessionId
      );
      if (existing) {
        currentSessionData = existing;
      } else {
        const raw = await ctx.db.get(args.currentSessionId);
        if (raw) {
          const exercises = await ctx.db
            .query("exercises")
            .withIndex("by_session", (q) =>
              q.eq("sessionId", args.currentSessionId!)
            )
            .collect();

          const exercisesWithSets = await Promise.all(
            exercises.map(async (exercise) => {
              const sets = await ctx.db
                .query("sets")
                .withIndex("by_exercise", (q) =>
                  q.eq("exerciseId", exercise._id)
                )
                .collect();
              return {
                name: exercise.name,
                order: exercise.order,
                sets: sets
                  .sort((a, b) => a.order - b.order)
                  .map((s) => ({
                    reps: s.reps,
                    weight: s.weight,
                    order: s.order,
                  })),
              };
            })
          );

          currentSessionData = {
            _id: raw._id as string,
            date: raw.date,
            status: raw.status,
            exercises: exercisesWithSets.sort((a, b) => a.order - b.order),
          };
        }
      }
    }

    // AI memories (non-archived)
    const memories = await ctx.db
      .query("aiMemories")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .collect();
    const activeMemories = memories.filter((m) => !m.archivedAt);

    // Completed sessions for recovery calc
    const completedSessions = sessionsWithExercises.filter(
      (s) => s.status === "completed"
    );

    // Build text
    const lines: string[] = [];

    lines.push(formatUserProfile(user));

    const recovery = formatRecovery(completedSessions);
    if (recovery) {
      lines.push(`RECOVERY: ${recovery}`);
    }

    const memStr = formatMemories(activeMemories);
    if (memStr) {
      lines.push(`MEMORIES: ${memStr}`);
    }

    // Build workout list: current session first (as TODAY), then history
    const allSessions: SessionWithExercises[] = [];
    if (currentSessionData) {
      allSessions.push(currentSessionData);
    }
    // Add history sessions, excluding the current one
    for (const s of sessionsWithExercises) {
      if (s._id !== currentSessionData?._id) {
        allSessions.push(s);
      }
    }

    if (allSessions.length > 0) {
      lines.push("");
      lines.push(
        currentSessionData
          ? "TODAY'S SESSION + RECENT WORKOUTS:"
          : `RECENT WORKOUTS (last ${limit} sessions):`
      );
      lines.push(
        formatWorkoutCSV(allSessions, currentSessionData?._id)
      );
    }

    return lines.join("\n");
  },
});
