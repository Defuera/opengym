"use node";
import { v } from "convex/values";
import { internalAction } from "../_generated/server";

/**
 * PDF text extraction. Needs Node (unpdf, a serverless build of pdf.js; pdf-parse needs DOMMatrix, which the Convex Node runtime lacks), so it lives alone in this file: only this file runs in the
 * Node runtime. Never throws: a problem becomes a note, as in the old backend.
 */
export const extract = internalAction({
  args: { storageId: v.id("_storage"), name: v.string() },
  handler: async (ctx, { storageId, name }): Promise<{ text?: string; note?: string }> => {
    const blob = await ctx.storage.get(storageId);
    if (!blob) return { note: `${name}: the stored file is missing.` };
    try {
      const { extractText, getDocumentProxy } = await import("unpdf");
      const pdf = await getDocumentProxy(new Uint8Array(await blob.arrayBuffer()));
      const text = (await extractText(pdf, { mergePages: true })).text.trim();
      return text ? { text } : { note: `${name}: PDF has no extractable text (scanned?).` };
    } catch (e) {
      return { note: `${name}: PDF text extraction is unavailable (${(e as Error).message}).` };
    }
  },
});
