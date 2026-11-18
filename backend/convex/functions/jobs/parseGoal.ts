import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { runAiJob } from "../lib/ai";
import { allSessions, goalByGoalId } from "../lib/db";
import { markFactsChanged } from "../lib/factsChanged";
import { goalKind } from "../lib/validators";
import { finalizeParsedGoal, parseGoalJob } from "../model/ai/jobs/parseGoal";

/** The AI budget for one goal text. The goal is already stored and shown; nothing waits for this. */
const BUDGET_MS = 25_000;
const MAX_NAMES = 150;

/** The goal text and the exercise names of the log (most recent first), or null when the goal is gone or its title changed. */
export const input = internalQuery({
  args: { goalId: v.string(), text: v.string() },
  handler: async (ctx, { goalId, text }) => {
    const goal = await goalByGoalId(ctx, goalId);
    if (!goal || goal.title !== text) return null;
    const seen = new Set<string>();
    const exercises: string[] = [];
    for (const s of (await allSessions(ctx)).reverse()) {
      for (const e of s.exercises) {
        if (!seen.has(e.name.toLowerCase())) {
          seen.add(e.name.toLowerCase());
          exercises.push(e.name);
        }
      }
    }
    return { text, exercises: exercises.slice(0, MAX_NAMES) };
  },
});

/**
 * Writes the structure fields (kind, exercise, targetKg, sessionsPerWeek) of a goal, and only those. It does nothing when the goal is gone
 * or its title is no longer the text that was read. Title and status never change. A fallback reading that found nothing changes nothing.
 * ADR-002: the structure is derived from the user's own text; it is not a new fact.
 */
export const save = internalMutation({
  args: {
    goalId: v.string(),
    text: v.string(),
    onlyFound: v.boolean(),
    kind: goalKind,
    exercise: v.optional(v.string()),
    targetKg: v.optional(v.number()),
    sessionsPerWeek: v.optional(v.number()),
  },
  handler: async (ctx, { goalId, text, onlyFound, kind, exercise, targetKg, sessionsPerWeek }) => {
    const goal = await goalByGoalId(ctx, goalId);
    if (!goal || goal.title !== text) return;
    if (onlyFound && targetKg === undefined && sessionsPerWeek === undefined) return;
    await ctx.db.patch(goal._id, { kind, exercise, targetKg, sessionsPerWeek });
    await markFactsChanged(ctx);
  },
});

/** parse_goal job: input query -> AI pipeline (one retry, then the code fallback) -> save. An unexpected error leaves the goal as it is. */
export const run = internalAction({
  args: { goalId: v.string(), text: v.string() },
  handler: async (ctx, { goalId, text }): Promise<void> => {
    try {
      const i = await ctx.runQuery(internal.jobs.parseGoal.input, { goalId, text });
      if (!i) return;
      const r = await runAiJob(ctx, parseGoalJob, i, { timeoutMs: BUDGET_MS });
      const g = finalizeParsedGoal(r.value, i.exercises);
      await ctx.runMutation(internal.jobs.parseGoal.save, {
        goalId,
        text,
        onlyFound: r.path !== "ai",
        kind: g.kind,
        ...(g.exercise !== undefined ? { exercise: g.exercise } : {}),
        ...(g.targetKg !== undefined ? { targetKg: g.targetKg } : {}),
        ...(g.sessionsPerWeek !== undefined ? { sessionsPerWeek: g.sessionsPerWeek } : {}),
      });
    } catch (e) {
      console.error(`[goal] parse failed: ${(e as Error).message}`);
    }
  },
});
