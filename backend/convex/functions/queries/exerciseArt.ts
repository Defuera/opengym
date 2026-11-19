import { ConvexError, v } from "convex/values";
import { query } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { artKey } from "../model/exerciseArt";

/** The art state of the given names (0..30), one item per name, same order. `url` is set only when the status is `ready`. */
export const get = query({
  args: { token: v.string(), names: v.array(v.string()) },
  handler: async (ctx, { token, names }) => {
    requireToken(token);
    if (names.length > 30) throw new ConvexError("names: at most 30 names");
    const out: { name: string; status: "none" | "pending" | "ready" | "failed"; url: string | null }[] = [];
    for (const name of names) {
      const key = artKey(name);
      const row = key ? await ctx.db.query("exerciseArt").withIndex("by_key", (q) => q.eq("key", key)).first() : null;
      const url = row?.status === "ready" && row.storageId ? await ctx.storage.getUrl(row.storageId) : null;
      out.push({ name, status: row ? row.status : "none", url });
    }
    return out;
  },
});
