import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { providerFor, runAiJob } from "../lib/ai";
import { allContext, allGoals, allSessions, startRequestById } from "../lib/db";
import { coachEntries, entryImageFiles, loadEntryImages } from "../lib/entriesDb";
import { activeLimits } from "../lib/limitsDb";
import { requestExerciseArt } from "../lib/exerciseArtDb";
import { allPlaces, createPlace } from "../lib/placesDb";
import { lastPlaceIdFor } from "../model/places";
import { startDraft } from "../lib/validators";
import { buildSessionJob } from "../model/ai/jobs/buildSession";
import { buildStartInput } from "../model/startInput";
import { checkedStartProposal, pickPlace, startOutcome } from "../model/startSave";

/** The AI budget for one request. The app gives up after 20 s and opens an empty session itself. */
const BUDGET_MS = 25_000;

/** Bounded model input for one request, or null when the request is gone or no longer pending. */
export const input = internalQuery({
  args: { requestId: v.string() },
  handler: async (ctx, { requestId }) => {
    const doc = await startRequestById(ctx, requestId);
    if (!doc || doc.status !== "pending") return null;
    const now = Date.now();
    // The pure part (the picture of the user, the places, the rules plan for the fallback) is in model/startInput.ts: the eval runner calls it too.
    const built = buildStartInput(
      { name: doc.name, text: doc.text, feedback: doc.feedback, previousPlan: doc.previousPlan },
      { sessions: await allSessions(ctx), goals: await allGoals(ctx), context: await allContext(ctx), limits: await activeLimits(ctx), places: await allPlaces(ctx), entries: await coachEntries(ctx, now), now },
    );
    return { ...built, entryImages: await entryImageFiles(ctx, now) };
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
    // A given name is fixed: the AI must not rename the session (model/startSave.ts holds the checks).
    const checked = checkedStartProposal(doc, proposal, sessions, await activeLimits(ctx));
    // The place (ADR-021), by plain code: the name the coach gave (a new name makes a place with an empty text), else the place of the
    // newest session of this activity (also on the rules fallback). None when neither is known.
    const pick = pickPlace(await allPlaces(ctx), proposal.place, lastPlaceIdFor(sessions, checked.type));
    const place = pick ? ("place" in pick ? pick.place : await createPlace(ctx, pick.newName)) : null;
    await ctx.db.patch(doc._id, {
      status: "ready",
      proposal: {
        kind: checked.kind,
        type: checked.type,
        ...(checked.focus ? { focus: checked.focus } : {}),
        ...(checked.minutes !== undefined ? { minutes: checked.minutes } : {}),
        ...(checked.reason ? { reason: checked.reason } : {}),
        ...(checked.plan ? { plan: { source: source ?? "rules", ...checked.plan } } : {}),
        ...(place ? { place: { placeId: place.placeId, name: place.name } } : {}),
      },
    });
    // Art for the exercises of the plan (the same logic as commands/exerciseArt:request, daily cap kept).
    if (checked.plan) await requestExerciseArt(ctx, checked.plan.exercises.map((e) => e.name.trim()).filter((n) => n.length > 0).slice(0, 12));
    // Background learning (ADR-021), never blocking: the newest feedback, else the note or text, is read for what it says about this place.
    const feedback = doc.feedback?.[doc.feedback.length - 1];
    const sentence = feedback ?? doc.text?.trim();
    if (place && sentence) await ctx.scheduler.runAfter(0, internal.jobs.places.learn, { placeId: place.placeId, source: feedback ? "feedback" : "note", sentence });
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
      // A feedback request is never answered with the rules plan: it would not respect the feedback. It fails and the app keeps the old proposal.
      const out = startOutcome(r, input);
      if (out.failed) {
        await ctx.runMutation(internal.jobs.startRequest.save, { requestId, failed: true });
        return;
      }
      await ctx.runMutation(internal.jobs.startRequest.save, { requestId, source: out.source, proposal: out.proposal });
    } catch (e) {
      console.error(`[start] request failed: ${(e as Error).message}`);
      await ctx.runMutation(internal.jobs.startRequest.save, { requestId, failed: true });
    }
  },
});
