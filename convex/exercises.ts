import { v } from "convex/values";
import { query } from "./_generated/server";

// Get exercises for a session
export const listBySession = query({
  args: { sessionId: v.id("sessions") },
  handler: async (ctx, args) => {
    const exercises = await ctx.db
      .query("exercises")
      .withIndex("by_session", (q) => q.eq("sessionId", args.sessionId))
      .collect();

    return exercises.sort((a, b) => a.order - b.order);
  },
});
