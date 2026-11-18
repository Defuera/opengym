import { ConvexError, v } from "convex/values";
import { internalMutation, mutation } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { entryRowByEntryId, stableJson, withoutSystemFields } from "../lib/db";
import { deleteFile } from "../lib/entriesDb";
import { markFactsChanged } from "../lib/factsChanged";
import { fileByFileId } from "../lib/files";
import { parseOrThrow } from "../lib/validate";
import { EntrySchema } from "../model/schema";
import { entryFields } from "../schema";

/**
 * Idempotent write of one log entry, keyed by the client-made entryId (ADR-017). Validated like EntrySchema:
 * a note or at least one file, text up to 2000, up to 10 files. Every fileId must be a registered file.
 * A file the update drops is deleted (row and blob). Resending the same entry changes nothing. A save for an entry marked as
 * deleted changes nothing and returns the id (ADR-020).
 */
export const save = mutation({
  args: { token: v.string(), entry: v.object(entryFields) },
  handler: async (ctx, { token, entry }) => {
    requireToken(token);
    const { entryId, ...rest } = entry;
    parseOrThrow(EntrySchema, { id: entryId, ...rest }, "entry");
    const old = await entryRowByEntryId(ctx, entryId);
    if (old?.deletedAt !== undefined) return entryId; // marked as deleted (ADR-020): a late resend must not bring it back
    for (const id of entry.fileIds) {
      if (!(await fileByFileId(ctx, id))) throw new ConvexError(`entry.fileIds: no registered file "${id}"`);
    }
    if (old && stableJson(withoutSystemFields(old)) === stableJson(entry)) return entryId; // resend, nothing changed
    if (old) {
      await ctx.db.replace(old._id, entry);
      for (const id of old.fileIds) if (!entry.fileIds.includes(id)) await deleteFile(ctx, id);
    } else {
      await ctx.db.insert("entries", entry);
    }
    return entryId;
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
    await ctx.db.patch(old._id, { deletedAt: Date.now() });
    await markFactsChanged(ctx);
    return true;
  },
});

/** Operator tool (`npx convex run`): clears the mark of an entry, if it is not erased yet. Returns true when it brought one back. */
export const restoreEntry = internalMutation({
  args: { entryId: v.string() },
  handler: async (ctx, { entryId }) => {
    const old = await entryRowByEntryId(ctx, entryId);
    if (!old || old.deletedAt === undefined) return false;
    await ctx.db.patch(old._id, { deletedAt: undefined });
    await markFactsChanged(ctx);
    return true;
  },
});
