import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireUser } from "../lib/auth";
import { type StoredLogDraft, logView } from "../model/logDraft";
import { proposalView } from "../model/proposalText";

/**
 * Messages of one thread, oldest first. Subscribe to it: the assistant message arrives live.
 * A message that holds a whole-session proposal (ADR-032) returns it for the app as `{ title?, exercises: [{ name, sets: "3 × 10" }], state }`:
 * "applied" once the person approved it; "stale" when a newer proposal came after it in the thread or the open session is another one
 * (or none); else "open". The stored plan details (rev, session id) stay on the server. The view has `type: "session"`.
 * A log draft of the log chat has `type: "log"`: `{ type, kind, summary, at (ms), session?: { type, focus?, minutes?, distanceKm?, exercises: [{ name, sets }] }, goal?, limit?, note?, state, entryId? }`
 * with `state` "open", "applied" (and then `entryId`) or "stale" (a newer proposal came after it). The Done reply holds `entryId`.
 */
export const list = query({
  args: { token: v.string(), threadId: v.string() },
  handler: async (ctx, { token, threadId }) => {
    const userId = await requireUser(ctx, token);
    const rows = await ctx.db.query("messages").withIndex("by_user_and_threadId", (q) => q.eq("userId", userId).eq("threadId", threadId)).order("asc").collect();
    const lastWith = rows.reduce((at, m, i) => (m.proposal ? i : at), -1);
    const sessionId = rows.some((m) => m.proposal) ? ((await ctx.db.query("openSession").withIndex("by_user", (q) => q.eq("userId", userId)).unique())?.id ?? null) : null;
    return rows.map((m, i) => {
      const { proposal, userId: _owner, ...rest } = m;
      void _owner;
      if (!proposal) return rest;
      if (proposal.type === "log") return { ...rest, proposal: logView(proposal as StoredLogDraft, proposal.appliedAt !== undefined ? "applied" : i < lastWith ? "stale" : "open") };
      const state = proposal.appliedAt !== undefined ? "applied" : i < lastWith || sessionId !== proposal.openSessionId ? "stale" : "open";
      return { ...rest, proposal: proposalView(proposal, state) };
    });
  },
});
