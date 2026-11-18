import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { fileByFileId, fileMeta } from "../lib/files";

/** Newest first by `at` (default 50, at most 200). Each item holds its files with a URL; a missing file is left out. */
export const recent = query({
  args: { token: v.string(), limit: v.optional(v.number()) },
  handler: async (ctx, { token, limit }) => {
    requireToken(token);
    const take = Math.max(1, Math.min(Math.floor(limit ?? 50), 200));
    const docs = await ctx.db.query("entries").withIndex("by_at").order("desc").take(take);
    return Promise.all(
      docs.map(async (d) => {
        const files = [];
        for (const id of d.fileIds) {
          const f = await fileByFileId(ctx, id);
          if (f) files.push({ ...fileMeta(f), url: await ctx.storage.getUrl(f.storageId) });
        }
        return { entryId: d.entryId, text: d.text, at: d.at, createdAt: d.createdAt, files };
      }),
    );
  },
});
