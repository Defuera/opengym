import { v } from "convex/values";
import { internal } from "../_generated/api";
import type { Doc } from "../_generated/dataModel";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { providerFor, runAiJob } from "../lib/ai";
import { entryByEntryId } from "../lib/db";
import { fileByFileId, loadAttachment, type FileDoc } from "../lib/files";
import { readEntryJob } from "../model/ai/jobs/readEntry";
import { localTime } from "../model/ai/jobs/shared";
import type { ImageInput } from "../model/ai/provider";
import { entryRead } from "../schema";

/** The AI budget for one entry. The entry is already stored and shown; nothing waits for this. */
const BUDGET_MS = 40_000;
const MAX_IMAGES = 4;
const MAX_FILE_CHARS = 6000;

const fileDoc = (f: Doc<"files">): FileDoc => ({ fileId: f.fileId, storageId: f.storageId, name: f.name, mime: f.mime, size: f.size, kind: f.kind, createdAt: f.createdAt });
const pending = (d: Doc<"entries"> | null, rev: string): d is Doc<"entries"> => !!d && d.read?.status === "pending" && d.read.rev === rev;

/** The entry and its files, or null when the entry is gone, was changed, or is already read. */
export const input = internalQuery({
  args: { entryId: v.string(), rev: v.string() },
  handler: async (ctx, { entryId, rev }) => {
    const d = await entryByEntryId(ctx, entryId);
    if (!pending(d, rev)) return null;
    const files: FileDoc[] = [];
    for (const id of d.fileIds) {
      const f = await fileByFileId(ctx, id);
      if (f) files.push(fileDoc(f));
    }
    return { text: d.text, at: d.at, files };
  },
});

/** Stores the label. It does nothing when the entry is gone or its text or files changed meanwhile (the newer run labels it). */
export const save = internalMutation({
  args: { entryId: v.string(), read: entryRead },
  handler: async (ctx, { entryId, read }) => {
    const d = await entryByEntryId(ctx, entryId);
    if (!pending(d, read.rev)) return;
    await ctx.db.patch(d._id, { read: { ...read, ...(d.read?.made ? { made: d.read.made } : {}) } });
  },
});

/**
 * read_entry job (ADR-031): input query -> files -> AI pipeline (one retry) -> save. There is no code fallback that can read a
 * photo, so a run with no AI answer ends in "failed" and the entry shows as the user wrote it. It never throws.
 */
export const run = internalAction({
  args: { entryId: v.string(), rev: v.string() },
  handler: async (ctx, { entryId, rev }): Promise<void> => {
    try {
      const i = await ctx.runQuery(internal.jobs.readEntry.input, { entryId, rev });
      if (!i) return;
      const takesImages = (await providerFor(ctx))?.supportsImages ?? false;
      const images: ImageInput[] = [];
      const files: { name: string; text: string }[] = [];
      for (const f of i.files) {
        if (f.kind === "image" && images.length >= MAX_IMAGES) continue;
        const a = await loadAttachment(ctx, f, takesImages);
        if (!a) continue;
        if (a.image) images.push(a.image);
        else if (f.kind !== "image") files.push({ name: f.name, text: (a.text ?? a.note ?? "").slice(0, MAX_FILE_CHARS) });
      }
      // Nothing the model can read: an image-only entry on a provider with no image input.
      if (!i.text.trim() && images.length === 0 && files.every((f) => !f.text)) {
        await ctx.runMutation(internal.jobs.readEntry.save, { entryId, read: { status: "failed", rev } });
        return;
      }
      const when = `${new Date(i.at).toISOString().slice(0, 10)} ${localTime(i.at)}`;
      const r = await runAiJob(ctx, readEntryJob, { text: i.text, when, files, images }, { timeoutMs: BUDGET_MS });
      await ctx.runMutation(internal.jobs.readEntry.save, {
        entryId,
        read: r.path === "ai" ? { status: "ready", rev, kind: r.value.kind, summary: r.value.summary } : { status: "failed", rev },
      });
    } catch (e) {
      console.error(`[entry] read failed: ${(e as Error).message}`);
      await ctx.runMutation(internal.jobs.readEntry.save, { entryId, read: { status: "failed", rev } });
    }
  },
});
