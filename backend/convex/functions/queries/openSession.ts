import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireToken } from "../lib/auth";

/** The open session (ADR-028), or `session: null` when there is none. The app subscribes to this. */
export const get = query({
  args: { token: v.string() },
  handler: async (ctx, { token }) => {
    requireToken(token);
    const row = await ctx.db.query("openSession").first();
    if (!row) return { session: null, rev: 0, updatedBy: null };
    const { _id, _creationTime, rev, updatedAt, updatedBy, ...session } = row;
    return { session, rev, updatedAt, updatedBy };
  },
});
