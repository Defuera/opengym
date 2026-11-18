import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { runAiJob } from "../lib/ai";
import { allSessions, sessionBySessionId, withoutSystemFields } from "../lib/db";
import { markFactsChanged, scheduleReview } from "../lib/factsChanged";
import { exercise } from "../schema";
import { coachPicture } from "../model/ai/jobs/coachPicture";
import { parseLogJob, structureOf, usualSets } from "../model/ai/jobs/parseLog";
import { dayWithWeekday } from "../model/logDate";
import { type Exercise, SessionSchema } from "../model/schema";
import { activityKey } from "../model/sessionShape";

/** The AI budget for one text. The session is already stored and shown; nothing waits for this. */
const BUDGET_MS = 25_000;
const MAX_KNOWN = 150;

/**
 * The text, the activity and the exercises of the log, or null when the session is gone, was edited, or is not pending
 * any more (the stored note is no longer the text this job was started for).
 */
export const input = internalQuery({
  args: { sessionId: v.string(), text: v.string() },
  handler: async (ctx, { sessionId, text }) => {
    const doc = await sessionBySessionId(ctx, sessionId);
    if (!doc || doc.parse !== "pending" || doc.note !== text) return null;
    const all = await allSessions(ctx);
    const now = Date.now();
    const known = coachPicture(all, [], [], [], [], now).exercisesTheUserKnows.slice(0, MAX_KNOWN);
    return {
      job: {
        activity: doc.type,
        text,
        today: dayWithWeekday(now),
        exercisesTheUserKnows: known.map((e) => ({ name: e.name, lastSets: e.lastSets, ...(e.measure ? { measure: e.measure } : {}) })),
      },
      usual: [...usualSets(all).values()],
      at: doc.startedAt,
      now,
    };
  },
});

/**
 * Writes the structure of a text-logged session and sets `parse` to done or failed. It does nothing when the session is gone,
 * is no longer pending, or its note is no longer the text that was read (the user edited it meanwhile: the user's word wins).
 * The note, the activity name and the source never change. A result that would break the session shape is not written: parse becomes failed.
 * Then the same "facts changed" and review scheduling as a save.
 */
export const save = internalMutation({
  args: {
    sessionId: v.string(),
    text: v.string(),
    parse: v.union(v.literal("done"), v.literal("failed")),
    startedAt: v.optional(v.number()),
    endedAt: v.optional(v.number()),
    focus: v.optional(v.string()),
    minutes: v.optional(v.number()),
    distanceKm: v.optional(v.number()),
    exercises: v.optional(v.array(exercise)),
  },
  handler: async (ctx, { sessionId, text, parse, ...found }) => {
    const doc = await sessionBySessionId(ctx, sessionId);
    if (!doc || doc.parse !== "pending" || doc.note !== text) return;
    const exercises = found.exercises ?? [];
    const patch = {
      ...(found.startedAt !== undefined ? { startedAt: found.startedAt, endedAt: found.endedAt ?? found.startedAt } : {}),
      ...(found.focus !== undefined ? { focus: found.focus } : {}),
      ...(found.minutes !== undefined ? { minutes: found.minutes } : {}),
      ...(found.distanceKm !== undefined ? { distanceKm: found.distanceKm } : {}),
      ...(exercises.length > 0 ? { kind: "gym" as const, exercises } : {}),
    };
    const { sessionId: id, parse: _parse, ...rest } = { ...withoutSystemFields(doc), ...patch };
    void _parse;
    const ok = parse === "done" && SessionSchema.safeParse({ id, ...rest }).success;
    await ctx.db.patch(doc._id, ok ? { ...patch, parse: "done" } : { parse: "failed" });
    await markFactsChanged(ctx);
    await scheduleReview(ctx, sessionId);
  },
});

/**
 * parse_log job: input query -> AI pipeline (one retry, then the regex fallback) -> save. `parse` becomes "failed" only when the
 * AI did not answer and the fallback read nothing. An unexpected error also ends in "failed", so the app never waits for ever.
 */
export const run = internalAction({
  args: { sessionId: v.string(), text: v.string() },
  handler: async (ctx, { sessionId, text }): Promise<void> => {
    try {
      const i = await ctx.runQuery(internal.jobs.parseLog.input, { sessionId, text });
      if (!i) return;
      const r = await runAiJob(ctx, parseLogJob, i.job, { timeoutMs: BUDGET_MS });
      const usual = new Map(i.usual.map((e) => [activityKey(e.name), e as Exercise]));
      const found = structureOf(r.value, usual, i.at, i.now);
      await ctx.runMutation(internal.jobs.parseLog.save, { sessionId, text, parse: r.path === "ai" || Object.keys(found).length > 0 ? "done" : "failed", ...found });
    } catch (e) {
      console.error(`[log] parse failed: ${(e as Error).message}`);
      await ctx.runMutation(internal.jobs.parseLog.save, { sessionId, text, parse: "failed" });
    }
  },
});
