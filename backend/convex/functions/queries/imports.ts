import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireUser } from "../lib/auth";
import { withoutUserId } from "../lib/db";

/** Import jobs, newest first. */
export const list = query({
  args: { token: v.string() },
  handler: async (ctx, { token }) => {
    const userId = await requireUser(ctx, token);
    return (await ctx.db.query("imports").withIndex("by_user_and_createdAt", (q) => q.eq("userId", userId)).order("desc").collect()).map(withoutUserId);
  },
});

/** One import job, or null. */
export const get = query({
  args: { token: v.string(), importId: v.string() },
  handler: async (ctx, { token, importId }) => {
    const userId = await requireUser(ctx, token);
    const job = await ctx.db.query("imports").withIndex("by_user_and_importId", (q) => q.eq("userId", userId).eq("importId", importId)).unique();
    return job ? withoutUserId(job) : null;
  },
});
