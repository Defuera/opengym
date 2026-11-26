import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireUser } from "../lib/auth";
import { debriefState } from "../lib/debriefDb";
import { sessionBySessionId } from "../lib/db";

/** A session that ended less than this long ago may still get its debrief: the app shows "the coach is looking at your session". */
export const REVIEW_PENDING_MS = 3 * 60_000;

/**
 * The review of one session (ADR-041). Never calls the AI.
 * A stored review comes back with `stored: true`: a new one has `message` and maybe `question` (`{ text, answers: [{ id, label }] }`), an old
 * one has `summary` and `changes`. `debrief` is `{ threadId, answered }` when the debrief chat was opened, else null.
 * No stored review: `review` is null (the AI had no answer, or the session is old: there is no fake review), and `pending` is true while the
 * session is less than REVIEW_PENDING_MS old, so the app can say the coach is still looking. `review` is null when the session does not exist or is marked as deleted.
 */
export const get = query({
  args: { token: v.string(), sessionId: v.string() },
  handler: async (ctx, { token, sessionId }) => {
    const userId = await requireUser(ctx, token);
    const session = await sessionBySessionId(ctx, userId, sessionId); // gone, or marked as deleted (ADR-020): null
    if (!session) return { review: null, stored: false };
    const doc = await ctx.db.query("reviews").withIndex("by_user_and_sessionId", (q) => q.eq("userId", userId).eq("sessionId", sessionId)).unique();
    if (!doc) return { review: null, stored: false, pending: Date.now() - session.endedAt < REVIEW_PENDING_MS };
    return {
      review: { sessionId, source: doc.source, ...(doc.summary !== undefined ? { summary: doc.summary } : {}), ...(doc.changes !== undefined ? { changes: doc.changes } : {}), ...(doc.message !== undefined ? { message: doc.message } : {}), ...(doc.question ? { question: doc.question } : {}) },
      stored: true,
      debrief: await debriefState(ctx, userId, sessionId),
    };
  },
});
