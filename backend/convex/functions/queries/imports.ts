import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireToken } from "../lib/auth";

/** Import jobs, newest first. */
export const list = query({
  args: { token: v.string() },
  handler: async (ctx, { token }) => {
    requireToken(token);
    return ctx.db.query("imports").withIndex("by_createdAt").order("desc").collect();
  },
});

/** One import job, or null. */
export const get = query({
  args: { token: v.string(), importId: v.string() },
  handler: async (ctx, { token, importId }) => {
    requireToken(token);
    return ctx.db.query("imports").withIndex("by_importId", (q) => q.eq("importId", importId)).unique();
  },
});
