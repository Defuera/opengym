import { ConvexError, v } from "convex/values";
import { mutation } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { fileByFileId, fileMeta } from "../lib/files";
import { MAX_FILE_BYTES, kindOf } from "../model/fileText";

/** Step 1 of an upload: a one-time URL the app POSTs the bytes to. The answer holds the storageId. */
export const generateUploadUrl = mutation({
  args: { token: v.string() },
  handler: async (ctx, { token }) => {
    requireToken(token);
    return ctx.storage.generateUploadUrl();
  },
});

/**
 * Step 2: record the uploaded blob as a file with a client-made fileId. Resending the same fileId
 * returns the stored row. The size limit (20 MB) is checked against the stored blob, not the client's claim.
 * An oversize blob cannot be deleted here (a thrown error rolls the delete back), so it stays unreferenced in storage.
 */
export const register = mutation({
  args: { token: v.string(), fileId: v.string(), storageId: v.id("_storage"), name: v.string(), mime: v.string(), size: v.number() },
  handler: async (ctx, { token, fileId, storageId, name, mime, size }) => {
    requireToken(token);
    if (!fileId || fileId.length > 100) throw new ConvexError("fileId: must be 1 to 100 characters");
    const old = await fileByFileId(ctx, fileId);
    if (old) return fileMeta(old);
    const stored = await ctx.db.system.get(storageId);
    if (!stored) throw new ConvexError("storageId: no uploaded file with this id");
    const actual = stored.size;
    if (actual > MAX_FILE_BYTES || size > MAX_FILE_BYTES) throw new ConvexError(`${name || "file"} is larger than 20 MB`);
    const fileName = name || "upload";
    const fileMime = mime || stored.contentType || "application/octet-stream";
    const doc = { fileId, storageId, name: fileName, mime: fileMime, size: actual, kind: kindOf(fileName, fileMime), createdAt: Date.now() };
    await ctx.db.insert("files", doc);
    return fileMeta(doc);
  },
});

/** Delete a file row and its stored blob. Returns false if unknown. Messages that name it keep the id; the coach skips a missing file. */
export const remove = mutation({
  args: { token: v.string(), fileId: v.string() },
  handler: async (ctx, { token, fileId }) => {
    requireToken(token);
    const f = await fileByFileId(ctx, fileId);
    if (!f) return false;
    await ctx.storage.delete(f.storageId);
    await ctx.db.delete(f._id);
    return true;
  },
});
