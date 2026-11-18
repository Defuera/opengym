import { internal } from "../_generated/api";
import { internalMutation } from "../_generated/server";
import { DELETE_AFTER_MS, PURGE_BATCH } from "../lib/constants";
import { deleteFile } from "../lib/entriesDb";

/**
 * Erases for good what was marked as deleted more than DELETE_AFTER_MS ago (ADR-020). Run hourly by crons.ts.
 * A session goes with its review row. A note goes with its file rows and blobs. At most PURGE_BATCH rows of each table per pass;
 * a full pass schedules the next one at once. The read models already left the rows out when they were marked, so no rebuild is needed.
 * These reads are deliberately raw: they look at marked rows only, through `by_deletedAt` (rows without a mark are before 0).
 */
export const run = internalMutation({
  args: {},
  handler: async (ctx): Promise<{ sessions: number; entries: number }> => {
    const cutoff = Date.now() - DELETE_AFTER_MS;
    const sessions = await ctx.db.query("sessions").withIndex("by_deletedAt", (q) => q.gt("deletedAt", 0).lt("deletedAt", cutoff)).take(PURGE_BATCH);
    for (const s of sessions) {
      const review = await ctx.db.query("reviews").withIndex("by_sessionId", (q) => q.eq("sessionId", s.sessionId)).unique();
      if (review) await ctx.db.delete(review._id);
      await ctx.db.delete(s._id);
    }
    const entries = await ctx.db.query("entries").withIndex("by_deletedAt", (q) => q.gt("deletedAt", 0).lt("deletedAt", cutoff)).take(PURGE_BATCH);
    for (const e of entries) {
      for (const id of e.fileIds) await deleteFile(ctx, id);
      await ctx.db.delete(e._id);
    }
    if (sessions.length >= PURGE_BATCH || entries.length >= PURGE_BATCH) await ctx.scheduler.runAfter(0, internal.jobs.purge.run, {});
    return { sessions: sessions.length, entries: entries.length };
  },
});
