import { internal } from "../_generated/api";
import { internalMutation } from "../_generated/server";
import { AI_CALL_KEEP_MS, DELETE_AFTER_MS, PURGE_BATCH } from "../lib/constants";
import { deleteFile } from "../lib/entriesDb";

/**
 * Erases for good what was marked as deleted more than DELETE_AFTER_MS ago (ADR-020). Run hourly by crons.ts.
 * A session goes with its review row and the photos of its comments. A note goes with its file rows and blobs. A program is erased as it is; the sessions logged on it stay (they are facts). At most PURGE_BATCH rows of each table per pass;
 * a full pass schedules the next one at once. The read models already left the rows out when they were marked, so no rebuild is needed.
 * Stored AI calls go AI_CALL_KEEP_MS (90 days) after they were made (ADR-027).
 * These reads are deliberately raw: they look at marked rows only, through `by_deletedAt` (rows without a mark are before 0), over ALL users (ADR-039):
 * the job reads no content and decides nothing for a user; every follow-up read (the review, the files) uses the `userId` of the marked row.
 */
export const run = internalMutation({
  args: {},
  handler: async (ctx): Promise<{ sessions: number; entries: number; programs: number; aiCalls: number }> => {
    const cutoff = Date.now() - DELETE_AFTER_MS;
    const sessions = await ctx.db.query("sessions").withIndex("by_deletedAt", (q) => q.gt("deletedAt", 0).lt("deletedAt", cutoff)).take(PURGE_BATCH);
    for (const s of sessions) {
      const review = await ctx.db.query("reviews").withIndex("by_user_and_sessionId", (q) => q.eq("userId", s.userId).eq("sessionId", s.sessionId)).unique();
      if (review) await ctx.db.delete(review._id);
      // The photos of the comments go with the session (ADR-043).
      for (const e of s.exercises) for (const id of e.commentFileIds ?? []) await deleteFile(ctx, s.userId, id);
      await ctx.db.delete(s._id);
    }
    const entries = await ctx.db.query("entries").withIndex("by_deletedAt", (q) => q.gt("deletedAt", 0).lt("deletedAt", cutoff)).take(PURGE_BATCH);
    for (const e of entries) {
      for (const id of e.fileIds) await deleteFile(ctx, e.userId, id);
      await ctx.db.delete(e._id);
    }
    const programs = await ctx.db.query("programs").withIndex("by_deletedAt", (q) => q.gt("deletedAt", 0).lt("deletedAt", cutoff)).take(PURGE_BATCH);
    for (const p of programs) await ctx.db.delete(p._id);
    const aiCalls = await ctx.db.query("aiCalls").withIndex("by_at", (q) => q.lt("at", Date.now() - AI_CALL_KEEP_MS)).take(PURGE_BATCH);
    for (const c of aiCalls) await ctx.db.delete(c._id);
    if (sessions.length >= PURGE_BATCH || entries.length >= PURGE_BATCH || programs.length >= PURGE_BATCH || aiCalls.length >= PURGE_BATCH) await ctx.scheduler.runAfter(0, internal.jobs.purge.run, {});
    return { sessions: sessions.length, entries: entries.length, programs: programs.length, aiCalls: aiCalls.length };
  },
});
