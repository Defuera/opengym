import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireUser } from "../lib/auth";

/** The open session (ADR-028), or `session: null` when there is none. The app subscribes to this. */
export const get = query({
  args: { token: v.string() },
  handler: async (ctx, { token }) => {
    const userId = await requireUser(ctx, token);
    const row = await ctx.db.query("openSession").withIndex("by_user", (q) => q.eq("userId", userId)).unique();
    if (!row) return { session: null, rev: 0, updatedBy: null };
    const { _id, _creationTime, userId: _owner, rev, updatedAt, updatedBy, ...session } = row;
    void _owner;
    return { session, rev, updatedAt, updatedBy };
  },
});
