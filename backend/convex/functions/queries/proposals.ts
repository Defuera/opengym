import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { PROPOSAL_OPEN_MAX } from "../lib/constants";
import { isStale, proposalByProposalId, proposalView } from "../lib/programsDb";

/** One proposal as the app reads it, or null when there is none (never made, or removed after 7 days). The app subscribes to it while the coach builds. */
export const get = query({
  args: { token: v.string(), proposalId: v.string() },
  handler: async (ctx, { token, proposalId }) => {
    requireToken(token);
    const d = await proposalByProposalId(ctx, proposalId);
    return d ? proposalView(d, await isStale(ctx, d)) : null;
  },
});

/**
 * The newest proposals still waiting for the person: status `building` or `ready` and approval `explicit` (at most 5, newest first), without
 * a change proposal that went stale. For the app after a restart.
 */
export const open = query({
  args: { token: v.string() },
  handler: async (ctx, { token }) => {
    requireToken(token);
    const docs = await ctx.db.query("proposals").withIndex("by_createdAt").order("desc").filter((f) => f.and(f.eq(f.field("approval"), "explicit"), f.or(f.eq(f.field("status"), "building"), f.eq(f.field("status"), "ready")))).take(PROPOSAL_OPEN_MAX * 4);
    const out = [];
    for (const d of docs) if (!(await isStale(ctx, d))) out.push(proposalView(d));
    return out.slice(0, PROPOSAL_OPEN_MAX);
  },
});
