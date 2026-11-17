import type { FileMeta } from "./schema";

/** Port of backend/api services/file-text.ts. Pure: no Node APIs (PDF parsing lives in jobs/pdfText.ts). */
export const CHUNK_CHARS = 12_000;
export const MAX_CHUNKS = 40;
export const MAX_FILE_BYTES = 20 * 1024 * 1024;

const TEXT_EXT = /\.(txt|md|markdown|csv|tsv|json|log)$/i;
const IMAGE_EXT: Record<string, string> = { png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif", webp: "image/webp" };

type Kind = FileMeta["kind"];

export function kindOf(name: string, mime: string): Kind {
  const m = mime.toLowerCase();
  const ext = name.split(".").pop()?.toLowerCase() ?? "";
  if (m.startsWith("image/") || ext in IMAGE_EXT) return "image";
  if (m === "application/pdf" || ext === "pdf") return "pdf";
  if (m.startsWith("audio/") || /^(m4a|mp3|wav|aac|ogg|opus)$/.test(ext)) return "audio";
  if (m.startsWith("text/") || m === "application/json" || TEXT_EXT.test(name)) return "text";
  return "other";
}

export function imageMime(meta: { name: string; mime: string }): string {
  if (meta.mime.startsWith("image/")) return meta.mime;
  return IMAGE_EXT[meta.name.split(".").pop()?.toLowerCase() ?? ""] ?? "image/jpeg";
}

export interface Extracted {
  text?: string;
  note?: string;
}

/** Text for every kind except pdf (the caller runs the Node action for pdf). */
export function extractPlain(meta: { name: string; kind: Kind }, bytes: Uint8Array): Extracted {
  if (meta.kind === "text") return { text: new TextDecoder().decode(bytes) };
  if (meta.kind === "audio") return { note: `${meta.name}: audio is stored but not transcribed.` };
  if (meta.kind === "image") return {};
  return { note: `${meta.name}: unsupported file type, stored only.` };
}

export function chunkText(text: string, size = CHUNK_CHARS, max = MAX_CHUNKS): { chunks: string[]; total: number } {
  const chunks: string[] = [];
  let i = 0;
  while (i < text.length) {
    let end = Math.min(text.length, i + size);
    if (end < text.length) {
      const nl = text.lastIndexOf("\n", end);
      if (nl > i + size / 2) end = nl + 1;
    }
    chunks.push(text.slice(i, end));
    i = end;
  }
  return { chunks: chunks.slice(0, max), total: chunks.length };
}

/** base64 without Buffer (the default Convex runtime has none). */
export function toBase64(bytes: Uint8Array): string {
  let bin = "";
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(bin);
}
