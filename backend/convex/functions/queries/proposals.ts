import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireUser } from "../lib/auth";
import { PROPOSAL_FOR_THREAD_MAX, PROPOSAL_OPEN_MAX } from "../lib/constants";
import { isStale, proposalByProposalId, proposalView } from "../lib/programsDb";

/** One proposal as the app reads it, or null when there is none (never made, or removed after 7 days). The app subscribes to it while the coach builds. */
export const get = query({
  args: { token: v.string(), proposalId: v.string() },
  handler: async (ctx, { token, proposalId }) => {
    const userId = await requireUser(ctx, token);
    const d = await proposalByProposalId(ctx, userId, proposalId);
    return d ? proposalView(d, await isStale(ctx, userId, d)) : null;
  },
});

/**
 * The newest proposals still waiting for the person: status `building` or `ready` and approval `explicit` (at most 5, newest first), without
 * a change proposal that went stale. For the app after a restart.
 */
export const open = query({
  args: { token: v.string() },
  handler: async (ctx, { token }) => {
    const userId = await requireUser(ctx, token);
    const docs = await ctx.db.query("proposals").withIndex("by_createdAt").order("desc").filter((f) => f.and(f.eq(f.field("approval"), "explicit"), f.or(f.eq(f.field("status"), "building"), f.eq(f.field("status"), "ready")))).take(PROPOSAL_OPEN_MAX * 4);
    const out = [];
    for (const d of docs) if (!(await isStale(ctx, userId, d))) out.push(proposalView(d));
    return out.slice(0, PROPOSAL_OPEN_MAX);
  },
});

/**
 * The proposals made in one chat thread (ADR-026), oldest first, at most 50. Same item shape as `get`, with the derived `stale`.
 * The app subscribes to it while the thread is open and matches a proposal to its message through `messages.proposalId`.
 */
export const forThread = query({
  args: { token: v.string(), threadId: v.string() },
  handler: async (ctx, { token, threadId }) => {
    const userId = await requireUser(ctx, token);
    const docs = await ctx.db.query("proposals").withIndex("by_threadId", (q) => q.eq("threadId", threadId)).order("asc").take(PROPOSAL_FOR_THREAD_MAX);
    const out = [];
    for (const d of docs) out.push(proposalView(d, await isStale(ctx, userId, d)));
    return out;
  },
});
