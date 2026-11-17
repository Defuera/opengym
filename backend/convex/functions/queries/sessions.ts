import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireToken } from "../lib/auth";

/** Newest first. The app subscribes to this, so every change arrives live. */
export const recent = query({
  args: { token: v.string(), limit: v.optional(v.number()) },
  handler: async (ctx, { token, limit }) => {
    requireToken(token);
    return ctx.db.query("sessions").withIndex("by_endedAt").order("desc").take(Math.min(limit ?? 20, 200));
  },
});

/** Sessions that ended after `since` (epoch ms), oldest first. For the app's sync. */
export const since = query({
  args: { token: v.string(), since: v.number() },
  handler: async (ctx, { token, since }) => {
    requireToken(token);
    return ctx.db.query("sessions").withIndex("by_endedAt", (q) => q.gt("endedAt", since)).order("asc").collect();
  },
});
