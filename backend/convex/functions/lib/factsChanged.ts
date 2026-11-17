import { internal } from "../_generated/api";
import type { MutationCtx } from "../_generated/server";
import { REBUILD_DEBOUNCE_MS } from "./constants";

/**
 * Called by every command that changes facts.
 *
 * It does NOT delete the current read models: the app keeps showing them. It only records
 * that facts changed and makes sure ONE runner is scheduled (jobs/rebuild:run). The runner
 * waits until writes have been quiet for REBUILD_DEBOUNCE_MS, then schedules the rebuild jobs.
 * So an import or a sync of ten sessions leads to one rebuild, not ten.
 */
export async function markFactsChanged(ctx: MutationCtx): Promise<void> {
  const now = Date.now();
  const state = await ctx.db.query("rebuilds").first();
  if (!state) {
    await ctx.db.insert("rebuilds", { dirtyAt: now, dirtySince: now, runnerScheduled: true, runs: 0 });
    await ctx.scheduler.runAfter(REBUILD_DEBOUNCE_MS, internal.jobs.rebuild.run, {});
    return;
  }
  if (state.runnerScheduled) {
    await ctx.db.patch(state._id, { dirtyAt: now });
    return;
  }
  await ctx.db.patch(state._id, { dirtyAt: now, dirtySince: now, runnerScheduled: true });
  await ctx.scheduler.runAfter(REBUILD_DEBOUNCE_MS, internal.jobs.rebuild.run, {});
}

/** Schedule the review job for one saved session. Not used for imports. */
export async function scheduleReview(ctx: MutationCtx, sessionId: string): Promise<void> {
  await ctx.scheduler.runAfter(0, internal.jobs.reviews.build, { sessionId, version: Date.now() });
}
