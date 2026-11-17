import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { runAiJob } from "../lib/ai";
import { allContext, allGoals, allSessions, planByFocus } from "../lib/db";
import { planExercise, proposalSource } from "../lib/validators";
import { buildPlanInput } from "../model/ai/jobs/inputs";
import { planSessionJob } from "../model/ai/jobs/planSession";
import { finalizePlan } from "../model/proposals";

/** Bounded model input for one plan. Reads the full history, returns the small input. */
export const input = internalQuery({
  args: { focus: v.string() },
  handler: async (ctx, { focus }) => buildPlanInput(await allSessions(ctx), await allGoals(ctx), await allContext(ctx), focus),
});

/** Applies the safety limits against the FULL history, then replaces the stored plan for the focus. */
export const save = internalMutation({
  args: {
    focus: v.string(),
    version: v.number(),
    source: proposalSource,
    draft: v.object({ rationale: v.string(), exercises: v.array(planExercise) }),
  },
  handler: async (ctx, { focus, version, source, draft }) => {
    const old = await planByFocus(ctx, focus);
    if (old && old.version > version) return; // a newer rebuild already stored its result
    const plan = finalizePlan(draft, await allSessions(ctx));
    const doc = { focus, version, createdAt: Date.now(), source, ...plan };
    if (old) await ctx.db.replace(old._id, doc);
    else await ctx.db.insert("plans", doc);
  },
});

/** plan_session job: input query -> AI pipeline -> save. */
export const build = internalAction({
  args: { focus: v.string(), version: v.number() },
  handler: async (ctx, { focus, version }): Promise<void> => {
    const input = await ctx.runQuery(internal.jobs.plans.input, { focus });
    const r = await runAiJob(planSessionJob, input);
    await ctx.runMutation(internal.jobs.plans.save, { focus, version, source: r.path === "ai" ? "ai" : "rules", draft: r.value });
  },
});
