import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalMutation } from "../_generated/server";
import { markFactsChanged } from "../lib/factsChanged";
import { purgeImportStep, writeImportItems } from "../lib/importWrite";
import { contextFields, goalFields, sessionFields } from "../schema";

/**
 * Writes one batch of an already validated structured import, then counts it on the job.
 * When the last batch lands the job turns `done` and one rebuild is requested.
 * Skips the batch if the job was removed or is no longer running.
 */
export const writeBatch = internalMutation({
  args: {
    userId: v.string(),
    importId: v.string(),
    sessions: v.optional(v.array(v.object(sessionFields))),
    goals: v.optional(v.array(v.object(goalFields))),
    context: v.optional(v.array(v.object(contextFields))),
  },
  handler: async (ctx, { userId, importId, ...items }) => {
    const job = await ctx.db.query("imports").withIndex("by_importId", (q) => q.eq("importId", importId)).unique();
    if (!job || job.status !== "running") return;
    const written = await writeImportItems(ctx, userId, items);
    const processed = job.processed + written;
    if (processed >= job.total) {
      await ctx.db.patch(job._id, { processed, status: "done" });
      await markFactsChanged(ctx, userId);
    } else {
      await ctx.db.patch(job._id, { processed });
    }
  },
});

/** Continues removing an import that was too big for one mutation. */
export const purge = internalMutation({
  args: { userId: v.string(), importId: v.string() },
  handler: async (ctx, { userId, importId }) => {
    if (!(await purgeImportStep(ctx, userId, importId))) await ctx.scheduler.runAfter(0, internal.jobs.imports.purge, { userId, importId });
  },
});
