import type { Doc } from "../_generated/dataModel";
import { ConvexError } from "convex/values";
import { internal } from "../_generated/api";
import type { ActionCtx, DatabaseReader, MutationCtx } from "../_generated/server";
import { entryByEntryId, entryRowByEntryId, liveEntryDocs, stableJson, toEntry, withoutSystemFields } from "./db";
import { parseOrThrow } from "./validate";
import { EntrySchema } from "../model/schema";
import { fileByFileId, loadAttachment, type FileDoc } from "./files";
import type { ImageInput } from "../model/ai/provider";
import { ensureCategory } from "./categoriesDb";
import type { CoachSourceEntry } from "../model/entryContext";

const DAY = 86_400_000;
/** What the coach reads of the entries (ADR-017). */
export const COACH_ENTRY_DAYS = 7;
export const COACH_ENTRY_MAX = 20;
export const COACH_IMAGE_HOURS = 24;
export const COACH_IMAGE_MAX = 4;

type Reader = { db: DatabaseReader };

/**
 * Entries of the last 7 days that the coach reads: the newest 20, oldest first. An entry that made a session (the log chat, ADR-032) is left out:
 * the session is read as training, so the same words are not read twice.
 */
export async function coachEntries(ctx: Reader, userId: string, now: number): Promise<CoachSourceEntry[]> {
  const docs = (await liveEntryDocs(ctx, userId, { order: "desc", from: now - COACH_ENTRY_DAYS * DAY, to: now, limit: COACH_ENTRY_MAX })).filter((d) => d.read?.made?.sessionId === undefined);
  return docs.reverse().map((d) => ({ ...toEntry(d), ...(d.fileIds.length > 0 && d.read?.status === "ready" && d.read.summary ? { seen: d.read.summary } : {}) }));
}

/** Names the text and the files of an entry: the reader job's label holds for exactly this pair (ADR-031). */
export function entryRev(e: { text: string; fileIds: string[] }): string {
  let h = 5381;
  for (const ch of JSON.stringify([e.text, e.fileIds])) h = ((h * 33) ^ ch.charCodeAt(0)) >>> 0;
  return `${h.toString(36)}-${e.text.length}-${e.fileIds.length}`;
}

const fileDoc = (f: Doc<"files">): FileDoc => ({ fileId: f.fileId, storageId: f.storageId, name: f.name, mime: f.mime, size: f.size, kind: f.kind, createdAt: f.createdAt });

/**
 * The image files of the entry the person has open, at most COACH_IMAGE_MAX. No entry in view: none. Photos of other entries
 * are not sent (their text and `seen` summary are already in the context). Bytes are read later, in an action.
 */
export async function entryInViewImageFiles(ctx: Reader, userId: string, entryId: string | undefined): Promise<FileDoc[]> {
  const entry = entryId ? await entryByEntryId(ctx, userId, entryId) : null;
  const out: FileDoc[] = [];
  for (const id of entry?.fileIds ?? []) {
    const f = await fileByFileId(ctx, userId, id);
    if (f && f.kind === "image") out.push(fileDoc(f));
    if (out.length >= COACH_IMAGE_MAX) break;
  }
  return out;
}

/** The image files of entries of the last 24 hours, newest entry first, at most 4. Only for building a session, which reads the last day (not for a chat). */
export async function entryImageFiles(ctx: Reader, userId: string, now: number): Promise<FileDoc[]> {
  const docs = await liveEntryDocs(ctx, userId, { order: "desc", from: now - COACH_IMAGE_HOURS * 3_600_000, to: now, limit: COACH_ENTRY_MAX });
  const out: FileDoc[] = [];
  for (const e of docs) {
    for (const id of e.fileIds) {
      const f = await fileByFileId(ctx, userId, id);
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
export async function deleteFile(ctx: Pick<MutationCtx, "db" | "storage">, userId: string, fileId: string): Promise<void> {
  const f = await fileByFileId(ctx, userId, fileId);
  if (!f) return;
  await ctx.storage.delete(f.storageId);
  await ctx.db.delete(f._id);
}

export interface EntryInput {
  entryId: string;
  text: string;
  fileIds: string[];
  at: number;
  createdAt: number;
  deletedAt?: number;
}

/** What the log chat knows when it writes an entry: the label is set by code and the reader job does not run (ADR-032). */
export interface EntryLabel {
  kind: string;
  summary: string;
  made?: { sessionId?: string; goalId?: string; limitId?: string; contextId?: string };
}

/**
 * The write of one log entry, shared by commands/entries:save and the log chat (ADR-017, ADR-032). Validated like EntrySchema, every file
 * registered, a dropped file deleted, a resend changes nothing, an entry marked as deleted stays so (ADR-020). A new or changed text or
 * file list starts the reader job (ADR-031), unless `label` is given: then the label is "ready" at once and no reader job is scheduled.
 */
export async function storeEntry(ctx: MutationCtx, userId: string, entry: EntryInput, label?: EntryLabel): Promise<string> {
  const { entryId, ...rest } = entry;
  parseOrThrow(EntrySchema, { id: entryId, ...rest }, "entry");
  const old = await entryRowByEntryId(ctx, userId, entryId);
  if (old?.deletedAt !== undefined) return entryId; // marked as deleted (ADR-020): a late resend must not bring it back
  for (const id of entry.fileIds) {
    if (!(await ctx.db.query("files").withIndex("by_fileId", (q) => q.eq("fileId", id)).unique())) throw new ConvexError(`entry.fileIds: no registered file "${id}"`);
  }
  if (old) {
    const { read: _read, ...was } = withoutSystemFields(old);
    void _read;
    if (stableJson(was) === stableJson(entry)) return entryId; // resend, nothing changed
  }
  // The reader job labels the entry (ADR-031). A label is kept only while the text and the files it read are the same.
  const rev = entryRev(entry);
  if (label) await ensureCategory(ctx, userId, label.kind, undefined, "rules");
  const made = label?.made ?? old?.read?.made;
  const read = label
    ? { status: "ready" as const, rev, kind: label.kind, summary: label.summary, ...(made ? { made } : {}) }
    : old?.read?.rev === rev
      ? old.read
      : { status: "pending" as const, rev, ...(made ? { made } : {}) };
  if (old) {
    await ctx.db.replace(old._id, { ...entry, read, userId });
    for (const id of old.fileIds) if (!entry.fileIds.includes(id)) await deleteFile(ctx, userId, id);
  } else {
    await ctx.db.insert("entries", { ...entry, read, userId });
  }
  if (read.status === "pending") await ctx.scheduler.runAfter(0, internal.jobs.readEntry.run, { userId, entryId, rev });
  return entryId;
}
