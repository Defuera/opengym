import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { runAiJob } from "../lib/ai";
import { allContext, allGoals, allSessions, startRequestById } from "../lib/db";
import { activeLimits } from "../lib/limitsDb";
import { startDraft } from "../lib/validators";
import { buildInterpretInput } from "../model/ai/jobs/inputs";
import { fallbackProposal, interpretRequestJob } from "../model/ai/jobs/interpretRequest";
import { finalizeStartProposal } from "../model/proposals";

/** The AI budget for one request. The app gives up after 20 s and opens an empty session itself. */
const BUDGET_MS = 25_000;

/** Bounded model input for one request, or null when the request is gone or no longer pending. */
export const input = internalQuery({
  args: { requestId: v.string() },
  handler: async (ctx, { requestId }) => {
    const doc = await startRequestById(ctx, requestId);
    if (!doc || doc.status !== "pending") return null;
    return buildInterpretInput(doc.text ?? "", await allSessions(ctx), await allGoals(ctx), await allContext(ctx), await activeLimits(ctx), Date.now(), doc.name, doc.mode === "today" ? { mode: "today", ...(doc.hintType ? { hint: { type: doc.hintType, ...(doc.hintFocus ? { focus: doc.hintFocus } : {}) } } : {}) } : undefined);
  },
});

/**
 * Stores the proposal and sets status "ready" (or "failed"). Only a pending request is changed, so a late or repeated job
 * changes nothing. Safety in code (ADR-004): the name reuses the log's spelling (activityKey), the focus is cut to 40,
 * the plan gets the weight caps, the size caps, the limits, and a size that fits the minutes asked for.
 */
export const save = internalMutation({
  args: { requestId: v.string(), failed: v.optional(v.boolean()), source: v.optional(v.union(v.literal("ai"), v.literal("rules"))), proposal: v.optional(startDraft) },
  handler: async (ctx, { requestId, failed, source, proposal }) => {
    const doc = await startRequestById(ctx, requestId);
    if (!doc || doc.status !== "pending") return;
    if (failed || !proposal) {
      await ctx.db.patch(doc._id, { status: "failed" });
      return;
    }
    const sessions = await allSessions(ctx);
    // A given name is fixed: the AI must not rename the session (finalizeStartProposal keeps the log's spelling).
    const checked = finalizeStartProposal(
      doc.name ? { ...proposal, type: doc.name } : proposal,
      sessions,
      await activeLimits(ctx),
    );
    await ctx.db.patch(doc._id, {
      status: "ready",
      proposal: {
        kind: checked.kind,
        type: checked.type,
        ...(checked.focus ? { focus: checked.focus } : {}),
        ...(checked.minutes !== undefined ? { minutes: checked.minutes } : {}),
        ...(checked.reason ? { reason: checked.reason } : {}),
        ...(checked.plan ? { plan: { source: source ?? "rules", ...checked.plan } } : {}),
      },
    });
  },
});

/** interpret_request job: input query -> AI pipeline (one retry, then the code fallback) -> save. Any unexpected error marks the request failed. */
export const build = internalAction({
  args: { requestId: v.string() },
  handler: async (ctx, { requestId }): Promise<void> => {
    try {
      const input = await ctx.runQuery(internal.jobs.startRequest.input, { requestId });
      if (!input) return;
      const r = await runAiJob(ctx, interpretRequestJob, input, { timeoutMs: BUDGET_MS });
      const proposal = r.path === "ai" ? r.value : fallbackProposal(input);
      await ctx.runMutation(internal.jobs.startRequest.save, { requestId, source: r.path === "ai" ? "ai" : "rules", proposal });
    } catch (e) {
      console.error(`[start] request failed: ${(e as Error).message}`);
      await ctx.runMutation(internal.jobs.startRequest.save, { requestId, failed: true });
    }
  },
});
