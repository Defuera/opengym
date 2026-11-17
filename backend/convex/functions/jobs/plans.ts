import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { runAiJob } from "../lib/ai";
import { allContext, allGoals, allSessions, planFor, planKey } from "../lib/db";
import { activeLimits } from "../lib/limitsDb";
import { planExercise, proposalSource } from "../lib/validators";
import { buildPlanInput } from "../model/ai/jobs/inputs";
import { planSessionJob } from "../model/ai/jobs/planSession";
import { finalizePlan } from "../model/proposals";
import { loggedName } from "../model/rules/foci";

/** Bounded model input for one plan. Reads the full history, returns the small input. */
export const input = internalQuery({
  args: { activity: v.string(), focus: v.optional(v.string()) },
  handler: async (ctx, { activity, focus }) => buildPlanInput(await allSessions(ctx), await allGoals(ctx), await allContext(ctx), activity, focus, await activeLimits(ctx)),
});

/** Applies the safety limits against the FULL history, then replaces the stored plan for the activity and focus. */
export const save = internalMutation({
  args: {
    activity: v.string(),
    focus: v.optional(v.string()),
    version: v.number(),
    source: proposalSource,
    draft: v.object({ rationale: v.string(), exercises: v.array(planExercise) }),
  },
  handler: async (ctx, { activity, focus, version, source, draft }) => {
    const old = await planFor(ctx, activity, focus);
    if (old && old.version > version) return; // a newer rebuild already stored its result
    const sessions = await allSessions(ctx);
    const plan = finalizePlan(draft, sessions, await activeLimits(ctx));
    const doc = {
      ...planKey(activity, focus),
      activity: loggedName(sessions, activity, "gym") ?? activity.trim(),
      ...(focus ? { focus: focus.trim() } : {}),
      version,
      createdAt: Date.now(),
      source,
      ...plan,
    };
    if (old) await ctx.db.replace(old._id, doc);
    else await ctx.db.insert("plans", doc);
  },
});

/** plan_session job: input query -> AI pipeline -> save. */
export const build = internalAction({
  args: { activity: v.string(), focus: v.optional(v.string()), version: v.number() },
  handler: async (ctx, { activity, focus, version }): Promise<void> => {
    const input = await ctx.runQuery(internal.jobs.plans.input, { activity, focus });
    const r = await runAiJob(planSessionJob, input);
    await ctx.runMutation(internal.jobs.plans.save, { activity, focus, version, source: r.path === "ai" ? "ai" : "rules", draft: r.value });
  },
});
