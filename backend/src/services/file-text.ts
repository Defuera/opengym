import type { FileMeta } from "../schema";

export const CHUNK_CHARS = 12_000;
export const MAX_CHUNKS = 40;

const TEXT_EXT = /\.(txt|md|markdown|csv|tsv|json|log)$/i;
const IMAGE_EXT: Record<string, string> = { png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif", webp: "image/webp" };

export function kindOf(name: string, mime: string): FileMeta["kind"] {
  const m = mime.toLowerCase();
  const ext = name.split(".").pop()?.toLowerCase() ?? "";
  if (m.startsWith("image/") || ext in IMAGE_EXT) return "image";
  if (m === "application/pdf" || ext === "pdf") return "pdf";
  if (m.startsWith("audio/") || /^(m4a|mp3|wav|aac|ogg|opus)$/.test(ext)) return "audio";
  if (m.startsWith("text/") || m === "application/json" || TEXT_EXT.test(name)) return "text";
  return "other";
}

export function imageMime(meta: FileMeta): string {
  if (meta.mime.startsWith("image/")) return meta.mime;
  return IMAGE_EXT[meta.name.split(".").pop()?.toLowerCase() ?? ""] ?? "image/jpeg";
}

export interface Extracted {
  text?: string;
  note?: string;
}

export async function extractText(meta: FileMeta, bytes: Uint8Array): Promise<Extracted> {
  if (meta.kind === "text") return { text: Buffer.from(bytes).toString("utf8") };
  if (meta.kind === "pdf") {
    try {
      const { PDFParse } = await import("pdf-parse");
      const parser = new PDFParse({ data: bytes });
      try {
        const res = await parser.getText();
        const text = res.text.trim();
        return text ? { text } : { note: `${meta.name}: PDF has no extractable text (scanned?).` };
      } finally {
        await parser.destroy();
      }
    } catch (e) {
      return { note: `${meta.name}: PDF text extraction is unavailable (${(e as Error).message}).` };
    }
  }
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
