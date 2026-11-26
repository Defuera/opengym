import { ConvexError, v } from "convex/values";
import { internal } from "../_generated/api";
import { mutation } from "../_generated/server";
import { requireUser } from "../lib/auth";
import { IMPORT_BATCH_SIZE, IMPORT_INLINE_MAX } from "../lib/constants";
import { fromSession, withoutSystemFields } from "../lib/db";
import { fileByFileId } from "../lib/files";
import { markFactsChanged } from "../lib/factsChanged";
import { purgeImportStep, writeImportItems } from "../lib/importWrite";
import { StructuredImportError, parseStructuredImport } from "../model/structuredImport";

const chunk = <T>(xs: T[], n: number): T[][] => Array.from({ length: Math.ceil(xs.length / n) }, (_, i) => xs.slice(i * n, (i + 1) * n));

/**
 * Port of POST /v1/import/structured. Validates EVERYTHING first; on an error nothing is written.
 * Up to IMPORT_INLINE_MAX documents are written here and the job is `done` at once.
 * A bigger import gets a `running` job and is written in batches by scheduled internal mutations
 * (jobs/imports:writeBatch), then the job turns `done`. Makes no AI call and queues no per-session review.
 * Pass your own importId to make a resend safe: the existing job comes back and nothing is written twice.
 */
export const loadStructured = mutation({
  args: {
    token: v.string(),
    importId: v.optional(v.string()),
    sessions: v.array(v.any()),
    goals: v.optional(v.array(v.any())),
    context: v.optional(v.array(v.any())),
    note: v.optional(v.string()),
  },
  handler: async (ctx, { token, importId: given, ...body }) => {
    const userId = await requireUser(ctx, token);
    const importId = given ?? crypto.randomUUID();
    const existing = await ctx.db.query("imports").withIndex("by_importId", (q) => q.eq("importId", importId)).unique();
    if (existing) return withoutSystemFields(existing);

    let parsed;
    try {
      parsed = parseStructuredImport(body, importId, () => crypto.randomUUID());
    } catch (e) {
      if (e instanceof StructuredImportError) throw new ConvexError(e.message);
      throw e;
    }
    const now = Date.now();
    const sessions = parsed.sessions.map(fromSession);
    const goals = parsed.goals.map((g) => ({ goalId: crypto.randomUUID(), ...g, status: "active" as const, source: "import" as const, importId, createdAt: now }));
    const context = parsed.context.map((c) => ({ itemId: crypto.randomUUID(), text: c.text, topic: c.topic, active: true, source: "import" as const, importId, createdAt: now }));
    const total = sessions.length + goals.length + context.length;
    const counts = { sessions: sessions.length, goals: goals.length, context: context.length };
    const notes = parsed.note ? [parsed.note] : [];

    if (total <= IMPORT_INLINE_MAX) {
      await writeImportItems(ctx, userId, { sessions, goals, context });
      const job = { userId, importId, status: "done" as const, total, processed: total, counts, notes, createdAt: now };
      await ctx.db.insert("imports", job);
      await markFactsChanged(ctx, userId);
      return job;
    }

    const job = { userId, importId, status: "running" as const, total, processed: 0, counts, notes, createdAt: now };
    await ctx.db.insert("imports", job);
    for (const batch of chunk(sessions, IMPORT_BATCH_SIZE)) await ctx.scheduler.runAfter(0, internal.jobs.imports.writeBatch, { userId, importId, sessions: batch });
    for (const batch of chunk(goals, IMPORT_BATCH_SIZE)) await ctx.scheduler.runAfter(0, internal.jobs.imports.writeBatch, { userId, importId, goals: batch });
    for (const batch of chunk(context, IMPORT_BATCH_SIZE)) await ctx.scheduler.runAfter(0, internal.jobs.imports.writeBatch, { userId, importId, context: batch });
    return job;
  },
});

/** Delete every session, goal and context item with this importId, and the job. Returns false if the job is unknown. */
export const remove = mutation({
  args: { token: v.string(), importId: v.string() },
  handler: async (ctx, { token, importId }) => {
    const userId = await requireUser(ctx, token);
    const job = await ctx.db.query("imports").withIndex("by_importId", (q) => q.eq("importId", importId)).unique();
    if (!job) return false;
    if (await purgeImportStep(ctx, userId, importId)) return true;
    // Too much for one mutation: stop any batch still writing, and continue in the background.
    await ctx.db.patch(job._id, { status: "failed", notes: [...job.notes, "Removal in progress."] });
    await ctx.scheduler.runAfter(0, internal.jobs.imports.purge, { userId, importId });
    return true;
  },
});

/**
 * Start an AI import of uploaded files (see commands/files). The job row is `running` at once; the app watches
 * `processed`, `total`, `counts` and `notes` on queries/imports:get. Resending the same importId returns the stored job.
 * The work runs in jobs/importFiles: one `import_data` call per text chunk or image, then ONE rebuild at the end.
 */
export const start = mutation({
  args: { token: v.string(), importId: v.string(), fileIds: v.array(v.string()) },
  handler: async (ctx, { token, importId, fileIds }) => {
    const userId = await requireUser(ctx, token);
    if (!importId || importId.length > 100) throw new ConvexError("importId: must be 1 to 100 characters");
    const existing = await ctx.db.query("imports").withIndex("by_importId", (q) => q.eq("importId", importId)).unique();
    if (existing) return withoutSystemFields(existing);
    if (fileIds.length < 1) throw new ConvexError("fileIds: send at least one file");
    for (const id of fileIds) if (!(await fileByFileId(ctx, userId, id))) throw new ConvexError(`file not found: ${id}`);
    const job = { userId, importId, status: "running" as const, total: fileIds.length, processed: 0, counts: { sessions: 0, goals: 0, context: 0 }, notes: [], createdAt: Date.now() };
    await ctx.db.insert("imports", job);
    await ctx.scheduler.runAfter(0, internal.jobs.importFiles.prepare, { userId, importId, fileIds });
    return job;
  },
});
