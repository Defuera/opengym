import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireUser } from "../lib/auth";
import { withoutUserId } from "../lib/db";

/** All context notes, oldest first. */
export const list = query({
  args: { token: v.string() },
  handler: async (ctx, { token }) => {
    const userId = await requireUser(ctx, token);
    return (await ctx.db.query("context").withIndex("by_user_and_createdAt", (q) => q.eq("userId", userId)).order("asc").collect()).map(withoutUserId);
  },
});
