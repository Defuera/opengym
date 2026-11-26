import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireUser } from "../lib/auth";
import { allGoals, allSessions } from "../lib/db";
import { dashboardDays } from "../lib/validators";
import { resolveDashboard, rulesSpec } from "../model/rules/dashboard";

/**
 * The dashboard for 7 or 30 days. Never calls the AI.
 * Only the layout spec is stored; every number is computed here from the full history (resolveDashboard).
 * With no stored layout (`stored: false`) the rules layout is used and `dashboard.source` is "rules".
 */
export const get = query({
  args: { token: v.string(), days: dashboardDays },
  handler: async (ctx, { token, days }) => {
    const userId = await requireUser(ctx, token);
    const goals = await allGoals(ctx, userId);
    const doc = await ctx.db.query("dashboards").withIndex("by_user_and_days", (q) => q.eq("userId", userId).eq("days", days)).unique();
    const spec = doc ? { source: doc.source, modules: doc.modules } : rulesSpec(goals);
    return { dashboard: resolveDashboard(spec, await allSessions(ctx, userId), goals, days, Date.now()), stored: doc !== null };
  },
});
