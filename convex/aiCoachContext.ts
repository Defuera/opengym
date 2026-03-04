import { internalQuery } from "./_generated/server";
import { v } from "convex/values";

/**
 * Build a compact CSV context block for the AI coach.
 * Includes: user profile, memories, recovery stats, and recent workouts.
 */
export const buildCoachContext = internalQuery({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const user = await ctx.db.get(args.userId);
    if (!user) return "";

    // Recent sessions (last 5, any status)
    const sessions = await ctx.db
      .query("sessions")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .order("desc")
      .take(5);

    // Fetch exercises + sets for each session
    const sessionRows: string[] = [];
    for (const session of sessions) {
      const exercises = await ctx.db
        .query("exercises")
        .withIndex("by_session", (q) => q.eq("sessionId", session._id))
        .collect();

      const sorted = exercises.sort((a, b) => a.order - b.order);

      for (const exercise of sorted) {
        const sets = await ctx.db
          .query("sets")
          .withIndex("by_exercise", (q) => q.eq("exerciseId", exercise._id))
          .collect();

        const sortedSets = sets.sort((a, b) => a.order - b.order);
        const setsStr = sortedSets
          .map((s) => (s.weight > 0 ? `${s.reps}x${s.weight}` : `${s.reps}`))
          .join(" → ");

        const date = formatDate(session.date);
        sessionRows.push(`${date},${exercise.name},${setsStr}`);
      }
    }

    // Recovery stats
    const now = Date.now();
    const completedSessions = sessions.filter((s) => s.status === "completed");
    const lastCompleted = completedSessions[0];
    const daysSinceLast = lastCompleted
      ? Math.floor((now - lastCompleted.date) / (1000 * 60 * 60 * 24))
      : null;
    const oneWeekAgo = now - 7 * 24 * 60 * 60 * 1000;
    const sessionsThisWeek = completedSessions.filter(
      (s) => s.date >= oneWeekAgo
    ).length;

    // AI memories
    const memories = await ctx.db
      .query("aiMemories")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .collect();
    const activeMemories = memories.filter((m) => !m.archivedAt);

    // Build the context string
    const lines: string[] = [];

    lines.push(`USER: ${user.name}, units: ${user.unit ?? "metric"}`);

    if (daysSinceLast !== null) {
      lines.push(
        `RECOVERY: ${daysSinceLast}d since last session, ${sessionsThisWeek} sessions this week`
      );
    }

    if (activeMemories.length > 0) {
      const memStr = activeMemories
        .map((m) => `${m.type}: ${m.key} = ${m.value}`)
        .join("; ");
      lines.push(`MEMORIES: ${memStr}`);
    }

    if (sessionRows.length > 0) {
      lines.push("");
      lines.push("RECENT WORKOUTS (last 5 sessions):");
      lines.push("date,exercise,sets");
      lines.push(...sessionRows);
    }

    return lines.join("\n");
  },
});

function formatDate(timestamp: number): string {
  const d = new Date(timestamp);
  const months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ];
  return `${months[d.getMonth()]} ${d.getDate()}`;
}
