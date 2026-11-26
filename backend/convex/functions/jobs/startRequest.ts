import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { providerFor, runAiJob } from "../lib/ai";
import { userTimezone } from "../lib/timezoneDb";
import { allContext, allGoals, allSessions, startRequestById } from "../lib/db";
import { coachTracker } from "../lib/trackerDb";
import { coachEntries, entryImageFiles, loadEntryImages } from "../lib/entriesDb";
import { activeLimits, limitsForAi } from "../lib/limitsDb";
import { requestExerciseArt } from "../lib/exerciseArtDb";
import { allPlaces, createPlace } from "../lib/placesDb";
import { liveProgramDocs, programByProgramId } from "../lib/programsDb";
import { localDate } from "../model/program";
import { programLinkFor } from "../model/programForCoach";
import { lastPlaceIdFor } from "../model/places";
import { startDraft } from "../lib/validators";
import { buildSessionJob } from "../model/ai/jobs/buildSession";
import { buildStartInput } from "../model/startInput";
import { checkedStartProposal, pickPlace, startOutcome } from "../model/startSave";

/** The AI budget for one request. The app gives up after 40 s and opens its own plan; an answer that comes later is offered on the session screen. */
const BUDGET_MS = 35_000;

/** Bounded model input for one request, or null when the request is gone or no longer pending. */
export const input = internalQuery({
  args: { userId: v.string(), requestId: v.string() },
  handler: async (ctx, { userId, requestId }) => {
    const doc = await startRequestById(ctx, userId, requestId);
    if (!doc || doc.status !== "pending") return null;
    const now = Date.now();
    const tz = await userTimezone(ctx, userId);
    // The pure part (the picture of the user, the places, the rules plan for the fallback) is in model/startInput.ts: the eval runner calls it too.
    const built = buildStartInput(
      { name: doc.name, text: doc.text, feedback: doc.feedback, previousPlan: doc.previousPlan, previousPlaceId: doc.previousPlaceId },
      { sessions: await allSessions(ctx, userId), goals: await allGoals(ctx, userId), context: await allContext(ctx, userId), limits: await limitsForAi(ctx, userId), places: await allPlaces(ctx, userId), entries: await coachEntries(ctx, userId, now), tracker: await coachTracker(ctx, userId, now, tz), programs: await liveProgramDocs(ctx, userId), now, timeZone: tz },
    );
    return { ...built, entryImages: await entryImageFiles(ctx, userId, now) };
  },
});

/**
 * Stores the proposal and sets status "ready" (or "failed"). Only a pending request is changed, so a late or repeated job
 * changes nothing. Safety in code (ADR-004): the name reuses the log's spelling (activityKey), the focus is cut to 40,
 * the plan gets the weight caps, the size caps, the limits, and a size that fits the minutes asked for.
 */
export const save = internalMutation({
  args: { userId: v.string(), requestId: v.string(), failed: v.optional(v.boolean()), source: v.optional(v.union(v.literal("ai"), v.literal("rules"))), proposal: v.optional(startDraft) },
  handler: async (ctx, { userId, requestId, failed, source, proposal }) => {
    const doc = await startRequestById(ctx, userId, requestId);
    if (!doc || doc.status !== "pending") return;
    if (failed || !proposal) {
      await ctx.db.patch(doc._id, { status: "failed" });
      return;
    }
    const sessions = await allSessions(ctx, userId);
    // A given name is fixed: the AI must not rename the session (model/startSave.ts holds the checks).
    const checked = checkedStartProposal(doc, proposal, sessions, await activeLimits(ctx, userId));
    // The place (ADR-021), by plain code: the name the coach gave (a new name makes a place with an empty text), else the place of the
    // newest session of this activity (also on the rules fallback). None when neither is known.
    const pick = pickPlace(await allPlaces(ctx, userId), proposal.place, lastPlaceIdFor(sessions, checked.type), doc.feedback && doc.previousPlaceId ? { previousPlaceId: doc.previousPlaceId, feedback: doc.feedback } : undefined);
    const place = pick ? ("place" in pick ? pick.place : await createPlace(ctx, userId, pick.newName)) : null;
    // The program link (ADR-030): the coach names the program session, code finds the week and the open slot. No open slot, no link.
    const link = proposal.program ? programLinkFor(await programByProgramId(ctx, userId, proposal.program.programId), proposal.program.key, sessions, localDate(Date.now(), await userTimezone(ctx, userId))) : null;
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
        ...(link ? { program: link } : {}),
      },
    });
    // Art for the exercises of the plan (the same logic as commands/exerciseArt:request, daily cap kept).
    if (checked.plan) await requestExerciseArt(ctx, userId, checked.plan.exercises.map((e) => e.name.trim()).filter((n) => n.length > 0).slice(0, 12));
    // Background learning (ADR-021), never blocking: the newest feedback, else the note or text, is read for what it says about this place.
    const feedback = doc.feedback?.[doc.feedback.length - 1];
    const sentence = feedback ?? doc.text?.trim();
    if (place && sentence) await ctx.scheduler.runAfter(0, internal.jobs.places.learn, { userId, placeId: place.placeId, source: feedback ? "feedback" : "note", sentence });
  },
});

/** build_session job: input query -> AI pipeline (one retry, then the code fallback) -> save. Any unexpected error marks the request failed. */
export const build = internalAction({
  args: { userId: v.string(), requestId: v.string() },
  handler: async (ctx, { userId, requestId }): Promise<void> => {
    try {
      const input = await ctx.runQuery(internal.jobs.startRequest.input, { userId, requestId });
      if (!input) return;
      // Photos of the entries of the last day go with the request when the provider takes images.
      const images = input.entryImages.length > 0 ? await loadEntryImages(ctx, input.entryImages, !!(await providerFor(ctx, userId))?.supportsImages) : [];
      const r = await runAiJob(ctx, userId, buildSessionJob, { ...input.job, ...(images.length > 0 ? { images } : {}) }, { timeoutMs: BUDGET_MS });
      // A feedback request is never answered with the rules plan: it would not respect the feedback. It fails and the app keeps the old proposal.
      const out = startOutcome(r, input);
      if (out.failed) {
        await ctx.runMutation(internal.jobs.startRequest.save, { userId, requestId, failed: true });
        return;
      }
      await ctx.runMutation(internal.jobs.startRequest.save, { userId, requestId, source: out.source, proposal: out.proposal });
    } catch (e) {
      console.error(`[start] request failed: ${(e as Error).message}`);
      await ctx.runMutation(internal.jobs.startRequest.save, { userId, requestId, failed: true });
    }
  },
});
