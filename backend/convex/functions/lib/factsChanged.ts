import { internal } from "../_generated/api";
import type { MutationCtx } from "../_generated/server";
import { REBUILD_DEBOUNCE_MS, REBUILD_MAX_WAIT_MS } from "./constants";

/**
 * Called by every command that changes facts of a user (ADR-039: the rebuild state is one row per user).
 *
 * It does NOT delete the current read models: the app keeps showing them. It only records
 * that facts changed and makes sure ONE runner is scheduled (jobs/rebuild:run). The runner
 * waits until writes have been quiet for REBUILD_DEBOUNCE_MS, then schedules the rebuild jobs.
 * So an import or a sync of ten sessions leads to one rebuild, not ten.
 */
export async function markFactsChanged(ctx: MutationCtx, userId: string): Promise<void> {
  const now = Date.now();
  const state = await ctx.db.query("rebuilds").withIndex("by_user", (q) => q.eq("userId", userId)).unique();
  if (!state) {
    await ctx.db.insert("rebuilds", { userId, dirtyAt: now, dirtySince: now, runnerScheduled: true, runs: 0 });
    await ctx.scheduler.runAfter(REBUILD_DEBOUNCE_MS, internal.jobs.rebuild.run, { userId });
    return;
  }
  // A runner that is scheduled picks the change up. One that has not run for longer than the debounce plus the max wait is lost (for example a job
  // queued under the arguments of an older deploy, which the new code refuses): a new runner is scheduled, so the flag cannot block rebuilds for ever.
  // Two runners are harmless: the second finds the flag off and returns.
  if (state.runnerScheduled && now - state.dirtyAt <= REBUILD_DEBOUNCE_MS + REBUILD_MAX_WAIT_MS) {
    await ctx.db.patch(state._id, { dirtyAt: now });
    return;
  }
  await ctx.db.patch(state._id, { dirtyAt: now, dirtySince: now, runnerScheduled: true });
  await ctx.scheduler.runAfter(REBUILD_DEBOUNCE_MS, internal.jobs.rebuild.run, { userId });
}

/** Schedule the review job for one saved session. Not used for imports. */
export async function scheduleReview(ctx: MutationCtx, userId: string, sessionId: string): Promise<void> {
  await ctx.scheduler.runAfter(0, internal.jobs.reviews.build, { userId, sessionId, version: Date.now() });
}
