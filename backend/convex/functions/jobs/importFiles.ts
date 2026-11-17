import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { providerFor, runAiJob } from "../lib/ai";
import { IMPORT_UNIT_STAGGER_MS } from "../lib/constants";
import { fromSession } from "../lib/db";
import { markFactsChanged } from "../lib/factsChanged";
import { type FileDoc, extractFileText, fileBytes, fileByFileId } from "../lib/files";
import { writeImportItems } from "../lib/importWrite";
import { type ImportInput, importDataJob } from "../model/ai/jobs/importData";
import { CHUNK_CHARS, MAX_CHUNKS, chunkText, imageMime, toBase64 } from "../model/fileText";
import { draftToSession } from "../model/importUnits";
import { ImportOutputSchema } from "../model/schema";

const jobOf = (ctx: { db: import("../_generated/server").DatabaseReader }, importId: string) =>
  ctx.db.query("imports").withIndex("by_importId", (q) => q.eq("importId", importId)).unique();

/** Notes keep their order and appear once. */
const mergeNotes = (old: string[], add: Iterable<string>) => [...new Set([...old, ...add])];

const unitArgs = {
  importId: v.string(),
  fileName: v.string(),
  fileCreatedAt: v.number(),
  uploadedAt: v.string(),
  chunk: v.optional(v.string()),
  chunkIndex: v.number(),
  chunkCount: v.number(),
  image: v.optional(v.object({ storageId: v.id("_storage"), mime: v.string() })),
};

export const files = internalQuery({
  args: { fileIds: v.array(v.string()) },
  handler: async (ctx, { fileIds }): Promise<FileDoc[]> => {
    const out: FileDoc[] = [];
    for (const id of fileIds) {
      const f = await fileByFileId(ctx, id);
      if (f) out.push({ fileId: f.fileId, storageId: f.storageId, name: f.name, mime: f.mime, size: f.size, kind: f.kind, createdAt: f.createdAt });
    }
    return out;
  },
});

export const isRunning = internalQuery({
  args: { importId: v.string() },
  handler: async (ctx, { importId }) => (await jobOf(ctx, importId))?.status === "running",
});

/** Sets the real unit count and the notes found while reading the files. With no units the job is done at once. */
export const plan = internalMutation({
  args: { importId: v.string(), total: v.number(), notes: v.array(v.string()) },
  handler: async (ctx, { importId, total, notes }): Promise<boolean> => {
    const job = await jobOf(ctx, importId);
    if (!job || job.status !== "running") return false;
    await ctx.db.patch(job._id, { total, notes: mergeNotes(job.notes, notes), ...(total === 0 ? { status: "done" as const } : {}) });
    if (total === 0) await markFactsChanged(ctx);
    return true;
  },
});

/** Ends the job as failed with a note. Units that run later see the status and stop. */
export const failJob = internalMutation({
  args: { importId: v.string(), error: v.string() },
  handler: async (ctx, { importId, error }) => {
    const job = await jobOf(ctx, importId);
    if (!job || job.status !== "running") return;
    await ctx.db.patch(job._id, { status: "failed", notes: mergeNotes(job.notes, [`Import failed: ${error}`]) });
  },
});

/**
 * Writes the result of one unit through the shared import write helper, tags everything with the importId,
 * and updates the live progress. The last unit turns the job `done` and requests ONE rebuild.
 * Skipped if the job was removed or is no longer running.
 */
export const applyUnit = internalMutation({
  args: { importId: v.string(), fileName: v.string(), fileCreatedAt: v.number(), output: v.any() },
  handler: async (ctx, { importId, fileName, fileCreatedAt, output }) => {
    const job = await jobOf(ctx, importId);
    if (!job || job.status !== "running") return;
    const out = ImportOutputSchema.parse(output);
    const notes = new Set<string>(out.notes.map((n) => `${fileName}: ${n}`));
    const now = Date.now();
    const sessions = out.sessions
      .map((d) => draftToSession(d, { name: fileName, createdAt: fileCreatedAt }, importId, () => crypto.randomUUID(), notes))
      .filter((s) => s !== null)
      .map(fromSession);
    const goals = out.goals.map((g) => ({ goalId: crypto.randomUUID(), ...g, status: "active" as const, source: "import" as const, importId, createdAt: now }));
    const context = out.context.map((c) => ({ itemId: crypto.randomUUID(), text: c.text, topic: c.topic, active: true, source: "import" as const, importId, createdAt: now }));
    await writeImportItems(ctx, { sessions, goals, context });
    const processed = job.processed + 1;
    const counts = { sessions: job.counts.sessions + sessions.length, goals: job.counts.goals + goals.length, context: job.counts.context + context.length };
    const done = processed >= job.total;
    await ctx.db.patch(job._id, { processed, counts, notes: mergeNotes(job.notes, notes), ...(done ? { status: "done" as const } : {}) });
    if (done) await markFactsChanged(ctx);
  },
});

/**
 * Reads the files, splits them into units (a text chunk or an image), sets the unit count, and schedules one
 * `unit` action per unit. Port of import-runner buildUnits. PDFs are read by the Node action in pdfText.ts.
 */
export const prepare = internalAction({
  args: { importId: v.string(), fileIds: v.array(v.string()) },
  handler: async (ctx, { importId, fileIds }): Promise<void> => {
    try {
      const provider = await providerFor(ctx);
      const notes = new Set<string>();
      const uploadedAt = new Date().toISOString();
      const units: Record<string, unknown>[] = [];
      for (const f of await ctx.runQuery(internal.jobs.importFiles.files, { fileIds })) {
        const base = { importId, fileName: f.name, fileCreatedAt: f.createdAt, uploadedAt };
        if (f.kind === "image") {
          if (provider && !provider.supportsImages) {
            notes.add(`${f.name}: ${provider.name} has no image input, so this photo was skipped.`);
            continue;
          }
          if (!(await ctx.storage.getUrl(f.storageId))) continue;
          units.push({ ...base, chunkIndex: 0, chunkCount: 1, image: { storageId: f.storageId, mime: imageMime(f) } });
          continue;
        }
        const bytes = await fileBytes(ctx, f);
        if (!bytes) continue;
        const ex = await extractFileText(ctx, f, bytes);
        if (ex.note) notes.add(ex.note);
        if (!ex.text) continue;
        const { chunks, total } = chunkText(ex.text);
        if (total > chunks.length) notes.add(`${f.name}: only the first ${MAX_CHUNKS} of ${total} chunks (${CHUNK_CHARS} chars each) were processed.`);
        chunks.forEach((chunk, i) => units.push({ ...base, chunk, chunkIndex: i, chunkCount: chunks.length }));
      }
      if (!(await ctx.runMutation(internal.jobs.importFiles.plan, { importId, total: units.length, notes: [...notes] }))) return;
      for (const [i, u] of units.entries()) {
        await ctx.scheduler.runAfter(i * IMPORT_UNIT_STAGGER_MS, internal.jobs.importFiles.unit, u as never);
      }
    } catch (e) {
      await ctx.runMutation(internal.jobs.importFiles.failJob, { importId, error: (e as Error).message });
    }
  },
});

/** One unit: runs the import_data job and writes the result. */
export const unit = internalAction({
  args: unitArgs,
  handler: async (ctx, a): Promise<void> => {
    try {
      if (!(await ctx.runQuery(internal.jobs.importFiles.isRunning, { importId: a.importId }))) return;
      const input: ImportInput = { fileName: a.fileName, uploadedAt: a.uploadedAt, chunk: a.chunk, chunkIndex: a.chunkIndex, chunkCount: a.chunkCount };
      if (a.image) {
        const blob = await ctx.storage.get(a.image.storageId);
        if (!blob) throw new Error(`${a.fileName}: the stored file is missing.`);
        input.image = { mime: a.image.mime, base64: toBase64(new Uint8Array(await blob.arrayBuffer())) };
      }
      const r = await runAiJob(ctx, importDataJob, input);
      await ctx.runMutation(internal.jobs.importFiles.applyUnit, { importId: a.importId, fileName: a.fileName, fileCreatedAt: a.fileCreatedAt, output: r.value });
    } catch (e) {
      await ctx.runMutation(internal.jobs.importFiles.failJob, { importId: a.importId, error: (e as Error).message });
    }
  },
});
