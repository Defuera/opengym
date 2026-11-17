import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireToken } from "../lib/auth";

/** All context notes, oldest first. */
export const list = query({
  args: { token: v.string() },
  handler: async (ctx, { token }) => {
    requireToken(token);
    return ctx.db.query("context").withIndex("by_createdAt").order("asc").collect();
  },
});
