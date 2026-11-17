import { internal } from "../_generated/api";
import { internalMutation } from "../_generated/server";
import { REBUILD_DEBOUNCE_MS, REBUILD_MAX_WAIT_MS } from "../lib/constants";
import { allSessions } from "../lib/db";
import { starterTypes } from "../model/rules/planner";

/**
 * The single scheduled runner behind lib/facts-changed.ts.
 * Re-checks the debounce: if facts changed again recently it waits again. When writes have been
 * quiet (or the max wait is over) it schedules one job per read model. Each job carries `version`
 * (the dirtyAt it rebuilds for), so an older result never replaces a newer one.
 */
export const run = internalMutation({
  args: {},
  handler: async (ctx): Promise<void> => {
    const state = await ctx.db.query("rebuilds").first();
    if (!state || !state.runnerScheduled) return;
    const now = Date.now();
    const quietFor = now - state.dirtyAt;
    const waited = now - state.dirtySince;
    if (quietFor < REBUILD_DEBOUNCE_MS && waited < REBUILD_MAX_WAIT_MS) {
      const wait = Math.min(REBUILD_DEBOUNCE_MS - quietFor, REBUILD_MAX_WAIT_MS - waited);
      await ctx.scheduler.runAfter(Math.max(wait, 1), internal.jobs.rebuild.run, {});
      return;
    }
    await ctx.db.patch(state._id, { runnerScheduled: false, runs: state.runs + 1, lastRunAt: now });
    const version = state.dirtyAt;
    const gymTypes = (await allSessions(ctx)).filter((s) => s.kind === "gym").map((s) => s.type);
    for (const type of new Set([...starterTypes, ...gymTypes])) await ctx.scheduler.runAfter(0, internal.jobs.plans.build, { type, version });
    await ctx.scheduler.runAfter(0, internal.jobs.predictions.build, { version });
    await ctx.scheduler.runAfter(0, internal.jobs.dashboards.build, { days: 7, version });
    await ctx.scheduler.runAfter(0, internal.jobs.dashboards.build, { days: 30, version });
  },
});
