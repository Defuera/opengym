import { internal } from "../_generated/api";
import type { Doc } from "../_generated/dataModel";
import type { ActionCtx, DatabaseReader } from "../_generated/server";
import { type AttachedFile } from "../model/coachContext";
import { extractPlain, imageMime, toBase64, type Extracted } from "../model/fileText";

export const fileByFileId = (ctx: { db: DatabaseReader }, userId: string, fileId: string) =>
  ctx.db.query("files").withIndex("by_user_and_fileId", (q) => q.eq("userId", userId).eq("fileId", fileId)).unique();

export type FileDoc = Pick<Doc<"files">, "fileId" | "storageId" | "name" | "mime" | "size" | "kind" | "createdAt">;

/** Bytes of a stored file, or null if the blob is gone. */
export async function fileBytes(ctx: ActionCtx, f: FileDoc): Promise<Uint8Array | null> {
  const blob = await ctx.storage.get(f.storageId);
  return blob ? new Uint8Array(await blob.arrayBuffer()) : null;
}

/** Text (or a note) for a file. PDFs go to the Node action in jobs/pdfText.ts. */
export async function extractFileText(ctx: ActionCtx, f: FileDoc, bytes: Uint8Array): Promise<Extracted> {
  if (f.kind === "pdf") return ctx.runAction(internal.jobs.pdfText.extract, { storageId: f.storageId, name: f.name });
  return extractPlain(f, bytes);
}

/** Reads one chat attachment. Images are loaded only when the provider can take them. */
export async function loadAttachment(ctx: ActionCtx, f: FileDoc, supportsImages: boolean): Promise<AttachedFile | null> {
  const bytes = await fileBytes(ctx, f);
  if (!bytes) return null;
  if (f.kind === "image") {
    return { meta: f, ...(supportsImages ? { image: { mime: imageMime(f), base64: toBase64(bytes) } } : {}) };
  }
  return { meta: f, ...(await extractFileText(ctx, f, bytes)) };
}

/** FileMeta of the contract: no storage id. */
export function fileMeta(d: { fileId: string; name: string; mime: string; size: number; kind: "text" | "image" | "pdf" | "audio" | "other"; createdAt: number }) {
  return { fileId: d.fileId, name: d.name, mime: d.mime, size: d.size, kind: d.kind, createdAt: d.createdAt };
}
