import { internal } from "../_generated/api";
import { v } from "convex/values";
import { internalMutation } from "../_generated/server";
import { REBUILD_DEBOUNCE_MS, REBUILD_MAX_WAIT_MS } from "../lib/constants";
import { allSessions, planKey } from "../lib/db";
import { rulesPredictions } from "../model/rules/predictions";

/** Plans precomputed per rebuild: the set-based items of the rules ranking (activity + focus due), at most this many (ADR-016). */
export const MAX_PRECOMPUTED_PLANS = 3;

/**
 * The single scheduled runner behind lib/facts-changed.ts.
 * Re-checks the debounce: if facts changed again recently it waits again. When writes have been
 * quiet (or the max wait is over) it schedules one job per read model. Each job carries `version`
 * (the dirtyAt it rebuilds for), so an older result never replaces a newer one.
 */
export const run = internalMutation({
  args: { userId: v.string() },
  handler: async (ctx, { userId }): Promise<void> => {
    const state = await ctx.db.query("rebuilds").withIndex("by_user", (q) => q.eq("userId", userId)).unique();
    if (!state || !state.runnerScheduled) return;
    const now = Date.now();
    const quietFor = now - state.dirtyAt;
    const waited = now - state.dirtySince;
    if (quietFor < REBUILD_DEBOUNCE_MS && waited < REBUILD_MAX_WAIT_MS) {
      const wait = Math.min(REBUILD_DEBOUNCE_MS - quietFor, REBUILD_MAX_WAIT_MS - waited);
      await ctx.scheduler.runAfter(Math.max(wait, 1), internal.jobs.rebuild.run, { userId });
      return;
    }
    await ctx.db.patch(state._id, { runnerScheduled: false, runs: state.runs + 1, lastRunAt: now });
    const version = state.dirtyAt;
    // Plans only for the set-based items of the rules ranking (max 3), so switching in the app needs no AI (ADR-003). The AI predict job is gone: the Start tab lists the log's activities.
    // Any other activity or focus is built by the rules fallback on read. Plan rows no longer wanted (and rows from before ADR-016,
    // which have no activity key) are removed: they are read models, rebuilt from the log.
    const sessions = await allSessions(ctx, userId);
    const current = rulesPredictions(sessions, now);
    const wanted = new Map<string, { activity: string; focus?: string }>();
    for (const p of current) {
      if (p.kind !== "gym" || wanted.size >= MAX_PRECOMPUTED_PLANS) continue;
      const k = planKey(p.type, p.focus);
      wanted.set(`${k.activityKey}|${k.focusKey}`, { activity: p.type, ...(p.focus ? { focus: p.focus } : {}) });
    }
    for (const plan of await ctx.db.query("plans").withIndex("by_user_and_focus", (q) => q.eq("userId", userId)).collect()) {
      if (plan.activityKey === undefined || !wanted.has(`${plan.activityKey}|${plan.focusKey ?? ""}`)) await ctx.db.delete(plan._id);
    }
    for (const w of wanted.values()) await ctx.scheduler.runAfter(0, internal.jobs.plans.build, { userId, ...w, version });
    await ctx.scheduler.runAfter(0, internal.jobs.dashboards.build, { userId, days: 7, version });
    await ctx.scheduler.runAfter(0, internal.jobs.dashboards.build, { userId, days: 30, version });
  },
});
