import { ConvexError, v } from "convex/values";
import { mutation } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { entryByEntryId, stableJson, withoutSystemFields } from "../lib/db";
import { deleteFile } from "../lib/entriesDb";
import { fileByFileId } from "../lib/files";
import { parseOrThrow } from "../lib/validate";
import { EntrySchema } from "../model/schema";
import { entryFields } from "../schema";

/**
 * Idempotent write of one log entry, keyed by the client-made entryId (ADR-017). Validated like EntrySchema:
 * a note or at least one file, text up to 2000, up to 10 files. Every fileId must be a registered file.
 * A file the update drops is deleted (row and blob). Resending the same entry changes nothing.
 */
export const save = mutation({
  args: { token: v.string(), entry: v.object(entryFields) },
  handler: async (ctx, { token, entry }) => {
    requireToken(token);
    const { entryId, ...rest } = entry;
    parseOrThrow(EntrySchema, { id: entryId, ...rest }, "entry");
    for (const id of entry.fileIds) {
      if (!(await fileByFileId(ctx, id))) throw new ConvexError(`entry.fileIds: no registered file "${id}"`);
    }
    const old = await entryByEntryId(ctx, entryId);
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

/** Delete one entry and its files (rows and blobs). False if the entry is unknown. */
export const remove = mutation({
  args: { token: v.string(), entryId: v.string() },
  handler: async (ctx, { token, entryId }) => {
    requireToken(token);
    const old = await entryByEntryId(ctx, entryId);
    if (!old) return false;
    for (const id of old.fileIds) await deleteFile(ctx, id);
    await ctx.db.delete(old._id);
    return true;
  },
});
