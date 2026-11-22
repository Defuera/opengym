import { v } from "convex/values";
import { internal } from "../_generated/api";
import { mutation } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { START_FEEDBACK_MAX, START_REQUEST_MAX_NAME, START_REQUEST_MAX_TEXT, START_REQUEST_PURGE_BATCH, START_REQUEST_TTL_MS } from "../lib/constants";
import { startRequestById } from "../lib/db";
import { compactPlan, feedbackChain } from "../lib/startFeedback";
import { previousPlan as previousPlanShape } from "../lib/validators";

/**
 * A "Start session" request (ADR-016). Idempotent by the client-made `requestId`: a resend changes nothing and
 * schedules nothing. Stores `{requestId, text?, name?, status: "pending"}` and schedules the build_session job
 * (jobs/startRequest:build). This is not a fact: the AI only proposes; the app saves a session after the user starts it.
 * `name` (optional, 1..40) is the fixed session name: the proposal type is always this name. `text` (optional, max 200)
 * is the note for today, or, with no name, the request. At least one of the two is required.
 * The Start tab sends `name` (the activity the user chose) and the optional note as `text`; "Other" sends only `text`
 * (what the user wants to do) and the coach names the activity. In both cases the coach decides the focus and the plan.
 * The old "today" mode (`mode`, `hintType`, `hintFocus`) is gone. Requests older than one day are removed here.
 * Feedback (ADR-016 follow-up): `feedback` (1..300 after trim) and `previousRequestId` come together or not at all. The new request
 * copies `name` and `text` from the previous row (it must still exist), keeps the earlier feedback of that row (an array, at most 5,
 * oldest dropped), and stores a compact copy of the previous proposal's plan. The job then rebuilds the session so the feedback
 * holds; when the AI fails the request is "failed" (no rules plan is returned for a feedback request). Given `name` or `text` next
 * to these two are ignored: the previous row decides.
 * Feedback on a session that did not come from a start request (a program session): `feedback` may come with `previousPlan` (the
 * compact plan shape of `startRequests.previousPlan`, sent by the app) INSTEAD of `previousRequestId`, together with `name` (1..40). Then
 * the row gets `name`, `feedback: [feedback]` and `previousPlan`, and the job works as for any rebuild. A `text` given here is kept as the
 * note for today (cut to the text limit): the app sends the note of the first request when its own plan replaced a late answer. Exactly one of
 * `previousRequestId` and `previousPlan` goes with `feedback`.
 * Returns the requestId.
 */
export const request = mutation({
  args: {
    token: v.string(),
    requestId: v.string(),
    text: v.optional(v.string()),
    name: v.optional(v.string()),
    feedback: v.optional(v.string()),
    previousRequestId: v.optional(v.string()),
    previousPlan: v.optional(previousPlanShape),
  },
  handler: async (ctx, { token, requestId, text, name, feedback, previousRequestId, previousPlan: givenPlan }): Promise<string> => {
    requireToken(token);
    const id = requestId.trim();
    if (id.length < 1 || id.length > 100) throw new Error("requestId must be 1..100 characters");
    if (feedback === undefined && (previousRequestId !== undefined || givenPlan !== undefined)) throw new Error("feedback and previousRequestId go together");
    if (feedback !== undefined && previousRequestId === undefined && givenPlan === undefined) throw new Error("feedback and previousRequestId go together (or previousPlan)");
    if (previousRequestId !== undefined && givenPlan !== undefined) throw new Error("give previousRequestId or previousPlan, not both");
    if (givenPlan !== undefined && (givenPlan.length < 1 || givenPlan.length > 30)) throw new Error("previousPlan must have 1..30 exercises");
    const cleanFeedback = feedback?.trim();
    if (cleanFeedback !== undefined && (cleanFeedback.length < 1 || cleanFeedback.length > START_FEEDBACK_MAX)) throw new Error(`feedback must be 1..${START_FEEDBACK_MAX} characters`);
    const prevId = previousRequestId?.trim();
    // A rebuild from a plan the app holds (no previous row): the name is the session name, and it is required.
    const planName = givenPlan ? name?.trim() : undefined;
    if (givenPlan && (!planName || planName.length > START_REQUEST_MAX_NAME)) throw new Error(`name must be 1..${START_REQUEST_MAX_NAME} characters`);
    if (prevId !== undefined && (prevId.length < 1 || prevId.length > 100)) throw new Error("previousRequestId must be 1..100 characters");
    const rebuild = cleanFeedback !== undefined;
    const cleanName = name?.trim();
    if (!rebuild && name !== undefined && (!cleanName || cleanName.length > START_REQUEST_MAX_NAME)) throw new Error(`name must be 1..${START_REQUEST_MAX_NAME} characters`);
    const clean = text?.trim();
    // Text is optional only when a name is given. An empty text next to a name means "no wish".
    if (!rebuild && text !== undefined && clean!.length > START_REQUEST_MAX_TEXT) throw new Error(`text must be 1..${START_REQUEST_MAX_TEXT} characters`);
    if (!rebuild && cleanName === undefined && (clean === undefined || clean.length < 1)) throw new Error(`text must be 1..${START_REQUEST_MAX_TEXT} characters (or give a name)`);
    const now = Date.now();
    const old = await ctx.db.query("startRequests").withIndex("by_createdAt", (q) => q.lt("createdAt", now - START_REQUEST_TTL_MS)).take(START_REQUEST_PURGE_BATCH);
    for (const d of old) await ctx.db.delete(d._id);
    if (await startRequestById(ctx, id)) return id;
    const prev = prevId !== undefined ? await startRequestById(ctx, prevId) : null;
    if (prevId !== undefined && !prev) throw new Error("previous request not found (it may be older than a day)");
    const plan = compactPlan(prev?.proposal?.plan);
    await ctx.db.insert("startRequests", {
      requestId: id,
      ...(givenPlan ? { name: planName!, ...(clean ? { text: clean.slice(0, START_REQUEST_MAX_TEXT) } : {}), feedback: [cleanFeedback!], previousPlan: givenPlan } : prev ? { ...(prev.text ? { text: prev.text } : {}), ...(prev.name ? { name: prev.name } : {}), feedback: feedbackChain(prev.feedback, cleanFeedback!), ...(plan ? { previousPlan: plan } : {}) } : { ...(clean ? { text: clean } : {}), ...(cleanName ? { name: cleanName } : {}) }),
      status: "pending",
      createdAt: now,
    });
    await ctx.scheduler.runAfter(0, internal.jobs.startRequest.build, { requestId: id });
    return id;
  },
});
