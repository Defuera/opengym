import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { fileByFileId, fileMeta } from "../lib/files";

/** FileMeta plus a URL that serves the bytes, or null if the file is unknown. */
export const get = query({
  args: { token: v.string(), fileId: v.string() },
  handler: async (ctx, { token, fileId }) => {
    requireToken(token);
    const f = await fileByFileId(ctx, fileId);
    if (!f) return null;
    return { ...fileMeta(f), url: await ctx.storage.getUrl(f.storageId) };
  },
});
