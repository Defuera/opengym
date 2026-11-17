import { v } from "convex/values";
import { mutation } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { sessionBySessionId, stableJson, withoutSystemFields } from "../lib/db";
import { markFactsChanged, scheduleReview } from "../lib/factsChanged";
import { parseOrThrow } from "../lib/validate";
import { SessionSchema } from "../model/schema";
import { sessionFields } from "../schema";

/**
 * Idempotent write of one session, keyed by the client-made sessionId.
 * Validated like SessionSchema (ranges, activity has no exercises, endedAt >= startedAt).
 * A changed session schedules a rebuild of the read models and, unless it came from an import, a review.
 */
export const save = mutation({
  args: { token: v.string(), session: v.object(sessionFields) },
  handler: async (ctx, { token, session }) => {
    requireToken(token);
    const { sessionId, ...rest } = session;
    parseOrThrow(SessionSchema, { id: sessionId, ...rest }, "session");
    const old = await sessionBySessionId(ctx, sessionId);
    if (old && stableJson(withoutSystemFields(old)) === stableJson(session)) return sessionId; // resend, nothing changed
    if (old) await ctx.db.replace(old._id, session);
    else await ctx.db.insert("sessions", session);
    await markFactsChanged(ctx);
    if (session.source !== "import") await scheduleReview(ctx, sessionId);
    return sessionId;
  },
});

/** Delete one session by its client-made id. No error if it is already gone. */
export const remove = mutation({
  args: { token: v.string(), sessionId: v.string() },
  handler: async (ctx, { token, sessionId }) => {
    requireToken(token);
    const old = await sessionBySessionId(ctx, sessionId);
    if (!old) return false;
    await ctx.db.delete(old._id);
    const review = await ctx.db.query("reviews").withIndex("by_sessionId", (q) => q.eq("sessionId", sessionId)).unique();
    if (review) await ctx.db.delete(review._id);
    await markFactsChanged(ctx);
    return true;
  },
});
