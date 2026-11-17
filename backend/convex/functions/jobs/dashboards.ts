import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { runAiJob } from "../lib/ai";
import { allContext, allGoals, allSessions } from "../lib/db";
import { dashboardDays, moduleSpec, proposalSource } from "../lib/validators";
import { buildDashboardInput } from "../model/ai/jobs/inputs";
import { buildDashboardJob } from "../model/ai/jobs/buildDashboard";

export const input = internalQuery({
  args: { days: dashboardDays },
  handler: async (ctx, { days }) => buildDashboardInput(await allSessions(ctx), await allGoals(ctx), await allContext(ctx), days),
});

/** Stores the layout spec only. Dashboard numbers are computed by code at query time (resolveDashboard). */
export const save = internalMutation({
  args: { days: dashboardDays, version: v.number(), source: proposalSource, modules: v.array(moduleSpec) },
  handler: async (ctx, { days, version, source, modules }) => {
    const old = await ctx.db.query("dashboards").withIndex("by_days", (q) => q.eq("days", days)).unique();
    if (old && old.version > version) return;
    // Drop goal modules whose goal is gone (same as the old refreshDashboard).
    const ids = new Set((await allGoals(ctx)).map((g) => g.id));
    const kept = modules.filter((m) => m.type !== "goal_progress" || ids.has(m.goalId));
    const doc = { days, version, createdAt: Date.now(), source, modules: kept };
    if (old) await ctx.db.replace(old._id, doc);
    else await ctx.db.insert("dashboards", doc);
  },
});

/** build_dashboard job. */
export const build = internalAction({
  args: { days: dashboardDays, version: v.number() },
  handler: async (ctx, { days, version }): Promise<void> => {
    const input = await ctx.runQuery(internal.jobs.dashboards.input, { days });
    const r = await runAiJob(buildDashboardJob, input);
    await ctx.runMutation(internal.jobs.dashboards.save, { days, version, source: r.path === "ai" ? "ai" : "rules", modules: r.value.modules });
  },
});
