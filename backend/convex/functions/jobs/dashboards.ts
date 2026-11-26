import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { runAiJob } from "../lib/ai";
import { userTimezone } from "../lib/timezoneDb";
import { allContext, allGoals, allSessions } from "../lib/db";
import { dashboardDays, moduleSpec, proposalSource } from "../lib/validators";
import { buildDashboardInput } from "../model/ai/jobs/inputs";
import { buildDashboardJob } from "../model/ai/jobs/buildDashboard";

export const input = internalQuery({
  args: { userId: v.string(), days: dashboardDays },
  handler: async (ctx, { userId, days }) => buildDashboardInput(await allSessions(ctx, userId), await allGoals(ctx, userId), await allContext(ctx, userId), days, await userTimezone(ctx, userId)),
});

/** Stores the layout spec only. Dashboard numbers are computed by code at query time (resolveDashboard). */
export const save = internalMutation({
  args: { userId: v.string(), days: dashboardDays, version: v.number(), source: proposalSource, modules: v.array(moduleSpec) },
  handler: async (ctx, { userId, days, version, source, modules }) => {
    const old = await ctx.db.query("dashboards").withIndex("by_user_and_days", (q) => q.eq("userId", userId).eq("days", days)).unique();
    if (old && old.version > version) return;
    // Drop goal modules whose goal is gone (same as the old refreshDashboard).
    const ids = new Set((await allGoals(ctx, userId)).map((g) => g.id));
    const kept = modules.filter((m) => m.type !== "goal_progress" || ids.has(m.goalId));
    const doc = { userId, days, version, createdAt: Date.now(), source, modules: kept };
    if (old) await ctx.db.replace(old._id, doc);
    else await ctx.db.insert("dashboards", doc);
  },
});

/** build_dashboard job. */
export const build = internalAction({
  args: { userId: v.string(), days: dashboardDays, version: v.number() },
  handler: async (ctx, { userId, days, version }): Promise<void> => {
    const input = await ctx.runQuery(internal.jobs.dashboards.input, { userId, days });
    const r = await runAiJob(ctx, userId, buildDashboardJob, input);
    await ctx.runMutation(internal.jobs.dashboards.save, { userId, days, version, source: r.path === "ai" ? "ai" : "rules", modules: r.value.modules });
  },
});
