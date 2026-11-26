import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireUser } from "../lib/auth";

/** All goals, oldest first. */
export const list = query({
  args: { token: v.string() },
  handler: async (ctx, { token }) => {
    const userId = await requireUser(ctx, token);
    return ctx.db.query("goals").withIndex("by_createdAt").order("asc").collect();
  },
});
