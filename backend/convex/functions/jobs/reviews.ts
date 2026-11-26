import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { runAiJob } from "../lib/ai";
import { userTimezone } from "../lib/timezoneDb";
import { coachTracker } from "../lib/trackerDb";
import { allContext, allGoals, allSessions, liveEntryDocs, sessionBySessionId, toSession } from "../lib/db";
import { liveProgramDocs } from "../lib/programsDb";
import { limitsForAi } from "../lib/limitsDb";
import { proposalSource } from "../lib/validators";
import { buildReviewInput } from "../model/ai/jobs/inputs";
import { reviewSessionJob } from "../model/ai/jobs/reviewSession";
import { finalizeReview } from "../model/proposals";

/** Bounded input for one review; null if the session is gone. */
export const input = internalQuery({
  args: { userId: v.string(), sessionId: v.string() },
  handler: async (ctx, { userId, sessionId }) => {
    const doc = await sessionBySessionId(ctx, userId, sessionId);
    const tz = await userTimezone(ctx, userId);
    // The entries of the day of the session (the body log of the day is part of the facts) and the programs of the person.
    const entries = doc ? (await liveEntryDocs(ctx, userId, { order: "asc", from: doc.startedAt - 86_400_000, to: doc.endedAt + 86_400_000, limit: 100 })).map((e) => ({ kind: e.read?.kind ?? "", text: e.text, at: e.at })) : [];
    return doc ? buildReviewInput(await allSessions(ctx, userId), toSession(doc), await limitsForAi(ctx, userId), { goals: await allGoals(ctx, userId), context: await allContext(ctx, userId), tracker: await coachTracker(ctx, userId, doc.startedAt, tz), timeZone: tz, entries, programs: await liveProgramDocs(ctx, userId) }) : null;
  },
});

/** Stores the debrief unless the session was deleted meanwhile or a newer review is stored. */
export const save = internalMutation({
  args: { userId: v.string(), sessionId: v.string(), version: v.number(), source: proposalSource, message: v.string(), question: v.optional(v.object({ text: v.string(), answers: v.array(v.string()) })) },
  handler: async (ctx, { userId, sessionId, version, source, ...draft }) => {
    if (!(await sessionBySessionId(ctx, userId, sessionId))) return;
    const old = await ctx.db.query("reviews").withIndex("by_user_and_sessionId", (q) => q.eq("userId", userId).eq("sessionId", sessionId)).unique();
    if (old && old.version > version) return;
    const doc = { userId, sessionId, version, createdAt: Date.now(), source, ...finalizeReview(draft) };
    if (old) await ctx.db.replace(old._id, doc);
    else await ctx.db.insert("reviews", doc);
  },
});

/** review_session job. Scheduled by commands/sessions:save, never for imports. */
export const build = internalAction({
  args: { userId: v.string(), sessionId: v.string(), version: v.number() },
  handler: async (ctx, { userId, sessionId, version }): Promise<void> => {
    const input = await ctx.runQuery(internal.jobs.reviews.input, { userId, sessionId });
    if (!input) return;
    const r = await runAiJob(ctx, userId, reviewSessionJob, input);
    // No AI answer: no review. A fake one (a count of the log) is worth less than none (ADR-041).
    if (r.path !== "ai") return;
    await ctx.runMutation(internal.jobs.reviews.save, { userId, sessionId, version, source: "ai", ...r.value });
  },
});
