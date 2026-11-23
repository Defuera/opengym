import type { Doc } from "../_generated/dataModel";
import type { ActionCtx, DatabaseReader, MutationCtx } from "../_generated/server";
import { liveEntryDocs, toEntry } from "./db";
import { fileByFileId, loadAttachment, type FileDoc } from "./files";
import type { ImageInput } from "../model/ai/provider";
import type { CoachSourceEntry } from "../model/entryContext";

const DAY = 86_400_000;
/** What the coach reads of the entries (ADR-017). */
export const COACH_ENTRY_DAYS = 7;
export const COACH_ENTRY_MAX = 20;
export const COACH_IMAGE_HOURS = 24;
export const COACH_IMAGE_MAX = 4;

type Reader = { db: DatabaseReader };

/** Entries of the last 7 days that the coach reads: the newest 20, oldest first. */
export async function coachEntries(ctx: Reader, now: number): Promise<CoachSourceEntry[]> {
  const docs = await liveEntryDocs(ctx, { order: "desc", from: now - COACH_ENTRY_DAYS * DAY, to: now, limit: COACH_ENTRY_MAX });
  return docs.reverse().map((d) => ({ ...toEntry(d), ...(d.fileIds.length > 0 && d.read?.status === "ready" && d.read.summary ? { seen: d.read.summary } : {}) }));
}

/** Names the text and the files of an entry: the reader job's label holds for exactly this pair (ADR-031). */
export function entryRev(e: { text: string; fileIds: string[] }): string {
  let h = 5381;
  for (const ch of JSON.stringify([e.text, e.fileIds])) h = ((h * 33) ^ ch.charCodeAt(0)) >>> 0;
  return `${h.toString(36)}-${e.text.length}-${e.fileIds.length}`;
}

const fileDoc = (f: Doc<"files">): FileDoc => ({ fileId: f.fileId, storageId: f.storageId, name: f.name, mime: f.mime, size: f.size, kind: f.kind, createdAt: f.createdAt });

/** The image files of entries of the last 24 hours, newest entry first, at most 4. Bytes are read later, in an action. */
export async function entryImageFiles(ctx: Reader, now: number): Promise<FileDoc[]> {
  const docs = await liveEntryDocs(ctx, { order: "desc", from: now - COACH_IMAGE_HOURS * 3_600_000, to: now, limit: COACH_ENTRY_MAX });
  const out: FileDoc[] = [];
  for (const e of docs) {
    for (const id of e.fileIds) {
      const f = await fileByFileId(ctx, id);
      if (f && f.kind === "image") out.push(fileDoc(f));
      if (out.length >= COACH_IMAGE_MAX) return out;
    }
  }
  return out;
}

/** Reads the image bytes for the coach. Empty when the provider takes no images. */
export async function loadEntryImages(ctx: ActionCtx, files: FileDoc[], supportsImages: boolean): Promise<ImageInput[]> {
  if (!supportsImages) return [];
  const images: ImageInput[] = [];
  for (const f of files) {
    const a = await loadAttachment(ctx, f, true);
    if (a?.image) images.push(a.image);
  }
  return images;
}

/** Deletes a file row and its blob. No error when it is gone. */
export async function deleteFile(ctx: Pick<MutationCtx, "db" | "storage">, fileId: string): Promise<void> {
  const f = await fileByFileId(ctx, fileId);
  if (!f) return;
  await ctx.storage.delete(f.storageId);
  await ctx.db.delete(f._id);
}
