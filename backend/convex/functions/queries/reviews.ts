import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireUser } from "../lib/auth";
import { allSessions, sessionBySessionId } from "../lib/db";
import { finalizeReview } from "../model/proposals";
import { rulesReview } from "../model/rules/review";

/**
 * The review of one session. Never calls the AI.
 * Stored review: `stored: true`. No stored review yet: the rules review computed here (`stored: false`,
 * source "rules"). `review` is null when the session does not exist or is marked as deleted.
 */
export const get = query({
  args: { token: v.string(), sessionId: v.string() },
  handler: async (ctx, { token, sessionId }) => {
    const userId = await requireUser(ctx, token);
    if (!(await sessionBySessionId(ctx, userId, sessionId))) return { review: null, stored: false }; // gone, or marked as deleted (ADR-020)
    const doc = await ctx.db.query("reviews").withIndex("by_sessionId", (q) => q.eq("sessionId", sessionId)).unique();
    if (doc) return { review: { sessionId, source: doc.source, summary: doc.summary, changes: doc.changes }, stored: true };
    const sessions = await allSessions(ctx, userId);
    const session = sessions.find((s) => s.id === sessionId);
    if (!session) return { review: null, stored: false };
    return { review: { sessionId, source: "rules" as const, ...finalizeReview(rulesReview(sessions, session)) }, stored: false };
  },
});
