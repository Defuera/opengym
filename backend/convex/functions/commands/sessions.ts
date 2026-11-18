import { ConvexError, v } from "convex/values";
import { internal } from "../_generated/api";
import { mutation } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { sessionBySessionId, stableJson, withoutSystemFields } from "../lib/db";
import { markFactsChanged, scheduleReview } from "../lib/factsChanged";
import { parseOrThrow } from "../lib/validate";
import { LogTextInputSchema, SessionSchema } from "../model/schema";
import { GYM_TYPE } from "../model/schema/common";
import { normalizeSession } from "../model/sessionShape";
import { sessionFields } from "../schema";

/**
 * Idempotent write of one session, keyed by the client-made sessionId.
 * Validated like SessionSchema (ranges, activity has no exercises, endedAt >= startedAt, type 1..40).
 * kind gym is a session with sets and may have any activity name in `type` (ADR-016); `type` may be left out
 * for it and is then "Gym". Legacy input is normalised first (an older app build or an old outbox entry): kind gym,
 * an old flavour name ("Upper") in type and no focus -> type "Gym", focus "Upper". The stored row always has the new shape.
 * A changed session schedules a rebuild of the read models and, unless it came from an import, a review.
 * `parse` (ADR-018) belongs to the parse_log job: a user save never writes it. It is left out of the stored row and of the
 * "nothing changed" comparison, so a resend of a row that still carries it changes nothing and a real edit clears it
 * (the user's edit is final: a parse_log result that arrives later is dropped).
 */
export const save = mutation({
  args: { token: v.string(), session: v.object({ ...sessionFields, type: v.optional(v.string()) }) },
  handler: async (ctx, { token, session: given }) => {
    requireToken(token);
    const { parse: _parse, ...clean } = given;
    void _parse;
    const session = normalizeSession({ ...clean, type: clean.type ?? (clean.kind === "gym" ? GYM_TYPE : "") });
    const { sessionId, ...rest } = session;
    parseOrThrow(SessionSchema, { id: sessionId, ...rest }, "session");
    const old = await sessionBySessionId(ctx, sessionId);
    if (old && stableJson(withoutSystemFields({ ...old, parse: undefined })) === stableJson(session)) return sessionId; // resend, nothing changed
    if (old) await ctx.db.replace(old._id, session);
    else await ctx.db.insert("sessions", session);
    await markFactsChanged(ctx);
    if (session.source !== "import") await scheduleReview(ctx, sessionId);
    return sessionId;
  },
});

/**
 * Logs an activity as one text (ADR-018). Idempotent by sessionId: the same id again changes nothing and schedules nothing.
 * The session is stored at once as a fact with what the user gave: the activity name `type`, the time `at`, no exercises and
 * the `text` word for word in `note`, with `parse: "pending"`. The parse_log job then fills the structure of THAT session
 * (minutes, distance, focus, the day, exercises); nothing waits for it. The review is scheduled when the job has written.
 */
export const logText = mutation({
  args: { token: v.string(), sessionId: v.string(), type: v.string(), text: v.string(), at: v.number() },
  handler: async (ctx, { token, sessionId, ...input }) => {
    requireToken(token);
    if (!sessionId || sessionId.length > 100) throw new ConvexError("sessionId: must be 1 to 100 characters");
    const valid = parseOrThrow(LogTextInputSchema, input, "log");
    if (await sessionBySessionId(ctx, sessionId)) return sessionId; // resend
    await ctx.db.insert("sessions", {
      sessionId,
      kind: "activity",
      type: valid.type,
      startedAt: valid.at,
      endedAt: valid.at,
      exercises: [],
      note: valid.text,
      source: "app",
      parse: "pending",
    });
    await markFactsChanged(ctx);
    await ctx.scheduler.runAfter(0, internal.jobs.parseLog.run, { sessionId, text: valid.text });
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
