import { v } from "convex/values";
import { internalMutation, mutation } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { entryRowByEntryId, sessionRowBySessionId } from "../lib/db";
import { storeEntry } from "../lib/entriesDb";
import { markFactsChanged } from "../lib/factsChanged";
import { entryFields } from "../schema";

/**
 * Idempotent write of one log entry, keyed by the client-made entryId (ADR-017). Validated like EntrySchema:
 * a note or at least one file, text up to 2000, up to 10 files. Every fileId must be a registered file.
 * A file the update drops is deleted (row and blob). A new or changed text or file list starts the reader job (ADR-031). Resending the same entry changes nothing. A save for an entry marked as
 * deleted changes nothing and returns the id (ADR-020).
 */
export const save = mutation({
  args: { token: v.string(), entry: v.object(entryFields) },
  handler: async (ctx, { token, entry }) => {
    requireToken(token);
    return storeEntry(ctx, entry);
  },
});

/**
 * Delete one entry (ADR-020): it only MARKS the row (`deletedAt` = now). Its files stay until jobs/purge erases entry, rows and
 * blobs DELETE_AFTER_MS later; `restoreEntry` undoes the mark before that. Idempotent: a second call keeps the first time.
 * Returns true when this call marked it, false when the entry is unknown or was already marked.
 */
export const remove = mutation({
  args: { token: v.string(), entryId: v.string() },
  handler: async (ctx, { token, entryId }) => {
    requireToken(token);
    const old = await entryRowByEntryId(ctx, entryId);
    if (!old || old.deletedAt !== undefined) return false;
    const now = Date.now();
    await ctx.db.patch(old._id, { deletedAt: now });
    // The session the log chat made with this entry goes with it (ADR-020). The goal, limit and note it made stay: nothing says cheaply whether the person edited them since.
    const made = old.read?.made?.sessionId;
    const session = made !== undefined ? await sessionRowBySessionId(ctx, made) : null;
    if (session && session.deletedAt === undefined) await ctx.db.patch(session._id, { deletedAt: now });
    await markFactsChanged(ctx);
    return true;
  },
});

/** Operator tool (`npx convex run`): clears the mark of an entry, and of the session it made, if not erased yet. Returns true when it brought one back. */
export const restoreEntry = internalMutation({
  args: { entryId: v.string() },
  handler: async (ctx, { entryId }) => {
    const old = await entryRowByEntryId(ctx, entryId);
    if (!old || old.deletedAt === undefined) return false;
    await ctx.db.patch(old._id, { deletedAt: undefined });
    const made = old.read?.made?.sessionId;
    const session = made !== undefined ? await sessionRowBySessionId(ctx, made) : null;
    if (session?.deletedAt !== undefined) await ctx.db.patch(session._id, { deletedAt: undefined });
    await markFactsChanged(ctx);
    return true;
  },
});
