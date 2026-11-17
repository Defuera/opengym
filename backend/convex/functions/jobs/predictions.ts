import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { runAiJob } from "../lib/ai";
import { allGoals, allSessions } from "../lib/db";
import { activeLimits } from "../lib/limitsDb";
import { prediction, proposalSource } from "../lib/validators";
import { buildPredictInput } from "../model/ai/jobs/inputs";
import { predictActivityJob } from "../model/ai/jobs/predictActivity";
import { rulesPredictions, validatePredictions } from "../model/rules/predictions";

export const input = internalQuery({
  args: {},
  handler: async (ctx) => buildPredictInput(await allSessions(ctx), await allGoals(ctx), Date.now(), await activeLimits(ctx)),
});

/**
 * Replaces the single stored predictions row. Validation after the model (ADR-004), in code: every activity must be in the log
 * (matched by activityKey, shown with the log's spelling), a focus must be one the log holds for that activity (else the focus
 * due), at most 2 items per activity and 6 in total. If nothing is left of the model's answer, the rules list is stored.
 * An empty log stores an empty list: nothing is invented.
 */
export const save = internalMutation({
  args: { version: v.number(), source: proposalSource, items: v.array(prediction) },
  handler: async (ctx, { version, source, items }) => {
    const old = await ctx.db.query("predictions").first();
    if (old && old.version > version) return;
    const sessions = await allSessions(ctx);
    const checked = validatePredictions(items, sessions);
    const useRules = checked.length === 0 && sessions.length > 0;
    const doc = { version, createdAt: Date.now(), source: useRules || sessions.length === 0 ? ("rules" as const) : source, items: useRules ? rulesPredictions(sessions, Date.now()) : checked };
    if (old) await ctx.db.replace(old._id, doc);
    else await ctx.db.insert("predictions", doc);
  },
});

/** predict_activity job. With an empty log there is nothing to rank: no AI call, an empty list. */
export const build = internalAction({
  args: { version: v.number() },
  handler: async (ctx, { version }): Promise<void> => {
    const input = await ctx.runQuery(internal.jobs.predictions.input, {});
    if (input.known.length === 0) {
      await ctx.runMutation(internal.jobs.predictions.save, { version, source: "rules", items: [] });
      return;
    }
    const r = await runAiJob(ctx, predictActivityJob, input);
    await ctx.runMutation(internal.jobs.predictions.save, { version, source: r.path === "ai" ? "ai" : "rules", items: r.value.predictions });
  },
});
