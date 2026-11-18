import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { providerFor, runAiJob } from "../lib/ai";
import { allContext, allGoals, allSessions, startRequestById } from "../lib/db";
import { coachEntries, entryImageFiles, loadEntryImages } from "../lib/entriesDb";
import { activeLimits } from "../lib/limitsDb";
import { startDraft } from "../lib/validators";
import { buildSessionJob } from "../model/ai/jobs/buildSession";
import { coachPicture } from "../model/ai/jobs/coachPicture";
import { knownActivities } from "../model/ai/jobs/inputs";
import { dropAvoided } from "../model/rules/limits";
import { rulesPlan } from "../model/rules/planner";
import { finalizeStartProposal } from "../model/proposals";
import { fallbackProposal, nameFromText } from "../model/startFallback";
import { activityKey } from "../model/sessionShape";

/** The AI budget for one request. The app gives up after 20 s and opens an empty session itself. */
const BUDGET_MS = 25_000;

/** Bounded model input for one request, or null when the request is gone or no longer pending. */
export const input = internalQuery({
  args: { requestId: v.string() },
  handler: async (ctx, { requestId }) => {
    const doc = await startRequestById(ctx, requestId);
    if (!doc || doc.status !== "pending") return null;
    const [sessions, goals, context, limits] = [await allSessions(ctx), await allGoals(ctx), await allContext(ctx), await activeLimits(ctx)];
    const now = Date.now();
    const known = knownActivities(sessions, now);
    // The plain rules plan of the named activity (the user's last session of it), for the fallback.
    const match = doc.name ? known.find((a) => activityKey(a.type) === activityKey(doc.name!)) : undefined;
    const rules = match?.kind === "gym" ? dropAvoided(rulesPlan(sessions, match.type), limits) : null;
    // The coach builds the session from the full picture of the user. A fixed name is the activity; with no name the coach names it from the text.
    const job = {
      name: doc.name ?? null,
      note: doc.name ? (doc.text ?? "") : "",
      ...(doc.name ? {} : { request: doc.text ?? "" }),
      picture: coachPicture(sessions, [...goals].sort((x, y) => x.createdAt - y.createdAt), context, limits, await coachEntries(ctx, now), now),
      limits,
    };
    return { job, known, text: doc.text ?? "", name: doc.name ?? null, rules, entryImages: await entryImageFiles(ctx, now) };
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
    // A given name is fixed: the AI must not rename the session. With no name the type is the coach's name, cut to 40
    // (finalizeStartProposal keeps the log's spelling).
    const type = doc.name ?? (proposal.type.trim().slice(0, 40).trim() || nameFromText(doc.text ?? ""));
    const checked = finalizeStartProposal(
      { ...proposal, type },
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

/** build_session job: input query -> AI pipeline (one retry, then the code fallback) -> save. Any unexpected error marks the request failed. */
export const build = internalAction({
  args: { requestId: v.string() },
  handler: async (ctx, { requestId }): Promise<void> => {
    try {
      const input = await ctx.runQuery(internal.jobs.startRequest.input, { requestId });
      if (!input) return;
      // Photos of the entries of the last day go with the request when the provider takes images.
      const images = input.entryImages.length > 0 ? await loadEntryImages(ctx, input.entryImages, !!(await providerFor(ctx))?.supportsImages) : [];
      const r = await runAiJob(ctx, buildSessionJob, { ...input.job, ...(images.length > 0 ? { images } : {}) }, { timeoutMs: BUDGET_MS });
      // Plain-code fallback: the activity with the rules plan from the log, or an empty plan when the log has none.
      const plain = fallbackProposal(input);
      const proposal = r.path === "ai" ? r.value : input.rules && input.rules.exercises.length > 0 ? { ...plain, plan: input.rules } : plain;
      await ctx.runMutation(internal.jobs.startRequest.save, { requestId, source: r.path === "ai" ? "ai" : "rules", proposal });
    } catch (e) {
      console.error(`[start] request failed: ${(e as Error).message}`);
      await ctx.runMutation(internal.jobs.startRequest.save, { requestId, failed: true });
    }
  },
});
