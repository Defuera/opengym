import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { runAiJob } from "../lib/ai";
import { allGoals, allSessions } from "../lib/db";
import { prediction, proposalSource } from "../lib/validators";
import { buildPredictInput } from "../model/ai/jobs/inputs";
import { predictActivityJob } from "../model/ai/jobs/predictActivity";

export const input = internalQuery({
  args: {},
  handler: async (ctx) => buildPredictInput(await allSessions(ctx), await allGoals(ctx), Date.now()),
});

/** Replaces the single stored predictions row. */
export const save = internalMutation({
  args: { version: v.number(), source: proposalSource, items: v.array(prediction) },
  handler: async (ctx, { version, source, items }) => {
    const old = await ctx.db.query("predictions").first();
    if (old && old.version > version) return;
    const doc = { version, createdAt: Date.now(), source, items };
    if (old) await ctx.db.replace(old._id, doc);
    else await ctx.db.insert("predictions", doc);
  },
});

/** predict_activity job. */
export const build = internalAction({
  args: { version: v.number() },
  handler: async (ctx, { version }): Promise<void> => {
    const input = await ctx.runQuery(internal.jobs.predictions.input, {});
    const r = await runAiJob(predictActivityJob, input);
    await ctx.runMutation(internal.jobs.predictions.save, { version, source: r.path === "ai" ? "ai" : "rules", items: r.value.predictions });
  },
});
