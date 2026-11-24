import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { proposalView } from "../model/proposalText";

/**
 * Messages of one thread, oldest first. Subscribe to it: the assistant message arrives live.
 * A message that holds a whole-session proposal (ADR-032) returns it for the app as `{ title?, exercises: [{ name, sets: "3 × 10" }], state }`:
 * "applied" once the person approved it; "stale" when a newer proposal came after it in the thread or the open session is another one
 * (or none); else "open". The stored plan details (rev, session id) stay on the server.
 */
export const list = query({
  args: { token: v.string(), threadId: v.string() },
  handler: async (ctx, { token, threadId }) => {
    requireToken(token);
    const rows = await ctx.db.query("messages").withIndex("by_threadId", (q) => q.eq("threadId", threadId)).order("asc").collect();
    const lastWith = rows.reduce((at, m, i) => (m.proposal ? i : at), -1);
    const sessionId = rows.some((m) => m.proposal) ? ((await ctx.db.query("openSession").first())?.id ?? null) : null;
    return rows.map((m, i) => {
      const { proposal, ...rest } = m;
      if (!proposal) return rest;
      const state = proposal.appliedAt !== undefined ? "applied" : i < lastWith || sessionId !== proposal.openSessionId ? "stale" : "open";
      return { ...rest, proposal: proposalView(proposal, state) };
    });
  },
});
