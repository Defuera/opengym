import { ConvexError, v } from "convex/values";
import { internal } from "../_generated/api";
import { internalMutation, mutation } from "../_generated/server";
import { requireUser } from "../lib/auth";
import { sessionBySessionId, sessionRowBySessionId, stableJson, withoutSystemFields } from "../lib/db";
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
 * `placeId` (ADR-021) is stored as given, even for an unknown place (the app may be ahead offline). A save WITHOUT it (an old app
 * build) keeps the stored one; only `setPlace` clears it.
 * The program link (`programId`, `programWeek`, `programSlot`, `programKey`, all optional) says which program session this is. The app
 * writes it when it starts a session from `queries/programs:list` `next`. Stored as given; a save without `programId` keeps the stored link.
 */
export const save = mutation({
  args: { token: v.string(), session: v.object({ ...sessionFields, type: v.optional(v.string()) }) },
  handler: async (ctx, { token, session: given }) => {
    const userId = await requireUser(ctx, token);
    const { parse: _parse, ...clean } = given;
    void _parse;
    const first = normalizeSession({ ...clean, type: clean.type ?? (clean.kind === "gym" ? GYM_TYPE : "") });
    const { sessionId, ...rest } = first;
    parseOrThrow(SessionSchema, { id: sessionId, ...rest }, "session");
    const old = await sessionRowBySessionId(ctx, userId, sessionId);
    const withPlace = first.placeId === undefined && old?.placeId !== undefined ? { ...first, placeId: old.placeId } : first;
    // The program link (like the place): an old app build does not send it, so a save without it keeps the stored one.
    const keepsLink = withPlace.programId === undefined && old?.programId !== undefined;
    const session = { userId, ...(keepsLink ? { ...withPlace, programId: old.programId, ...(old.programWeek !== undefined ? { programWeek: old.programWeek } : {}), ...(old.programSlot !== undefined ? { programSlot: old.programSlot } : {}), ...(old.programKey !== undefined ? { programKey: old.programKey } : {}) } : withPlace) };
    if (old?.deletedAt !== undefined) return sessionId; // marked as deleted (ADR-020): a late resend must not bring it back
    if (old && stableJson(withoutSystemFields({ ...old, parse: undefined })) === stableJson(session)) return sessionId; // resend, nothing changed
    if (old) await ctx.db.replace(old._id, session);
    else await ctx.db.insert("sessions", session);
    await markFactsChanged(ctx, userId);
    if (session.source !== "import") await scheduleReview(ctx, userId, sessionId);
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
    const userId = await requireUser(ctx, token);
    if (!sessionId || sessionId.length > 100) throw new ConvexError("sessionId: must be 1 to 100 characters");
    const valid = parseOrThrow(LogTextInputSchema, input, "log");
    if (await sessionRowBySessionId(ctx, userId, sessionId)) return sessionId; // resend, or marked as deleted (ADR-020): a late resend must not bring it back
    await ctx.db.insert("sessions", {
      userId,
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
    await markFactsChanged(ctx, userId);
    await ctx.scheduler.runAfter(0, internal.jobs.parseLog.run, { userId, sessionId, text: valid.text });
    return sessionId;
  },
});

/**
 * Delete one session by its client-made id (ADR-020): it only MARKS the row (`deletedAt` = now). Nothing else goes now, not the
 * review: jobs/purge erases both DELETE_AFTER_MS later, and `restoreSession` undoes the mark before that. Every read leaves a
 * marked row out. Idempotent: a second call keeps the first time. Returns true when this call marked it, false when the session
 * is unknown or was already marked (gone for the app either way).
 */
export const remove = mutation({
  args: { token: v.string(), sessionId: v.string() },
  handler: async (ctx, { token, sessionId }) => {
    const userId = await requireUser(ctx, token);
    const old = await sessionRowBySessionId(ctx, userId, sessionId);
    if (!old || old.deletedAt !== undefined) return false;
    await ctx.db.patch(old._id, { deletedAt: Date.now() });
    await markFactsChanged(ctx, userId);
    return true;
  },
});

/** Operator tool (`npx convex run`, args `{ userId, sessionId }`): clears the mark of a session, if it is not erased yet. Returns true when it brought one back. */
export const restoreSession = internalMutation({
  args: { userId: v.string(), sessionId: v.string() },
  handler: async (ctx, { userId, sessionId }) => {
    const old = await sessionRowBySessionId(ctx, userId, sessionId);
    if (!old || old.deletedAt === undefined) return false;
    await ctx.db.patch(old._id, { deletedAt: undefined });
    await markFactsChanged(ctx, userId);
    return true;
  },
});

/**
 * Sets or clears (`null`) the place of one session (ADR-021). Nothing else on the row changes, and no rebuild or review is scheduled:
 * the place is not part of the plan or the numbers. The place id is stored as given (an unknown id is fine). Returns false when the
 * session is unknown or marked as deleted, true otherwise.
 */
export const setPlace = mutation({
  args: { token: v.string(), sessionId: v.string(), placeId: v.union(v.string(), v.null()) },
  handler: async (ctx, { token, sessionId, placeId }) => {
    const userId = await requireUser(ctx, token);
    if (placeId !== null && (placeId.length < 1 || placeId.length > 100)) throw new ConvexError("placeId: must be 1 to 100 characters");
    const doc = await sessionBySessionId(ctx, userId, sessionId);
    if (!doc) return false;
    await ctx.db.patch(doc._id, { placeId: placeId ?? undefined });
    return true;
  },
});
