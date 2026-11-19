import type { ImageInput } from "./ai/provider";
import type { AttachedFile } from "./coachContext";
import { CHUNK_CHARS } from "./fileText";

/**
 * The files of a chat as a program build reads them: the text of documents (each cut at CHUNK_CHARS), the names of images, and the images
 * themselves when the provider takes them. A note of a file that could not be read goes in as its text.
 */
export function attachmentsForPrompt(files: AttachedFile[], supportsImages: boolean): { attachedFiles: { name: string; text: string }[]; attachedImages: string[]; images: ImageInput[] } {
  const attachedFiles: { name: string; text: string }[] = [];
  const attachedImages: string[] = [];
  const images: ImageInput[] = [];
  for (const f of files) {
    if (f.meta.kind === "image") {
      if (supportsImages && f.image) {
        images.push(f.image);
        attachedImages.push(f.meta.name);
      } else attachedFiles.push({ name: f.meta.name, text: "(an image this AI provider cannot read)" });
    } else if (f.text) attachedFiles.push({ name: f.meta.name, text: f.text.slice(0, CHUNK_CHARS) });
    else if (f.note) attachedFiles.push({ name: f.meta.name, text: f.note });
  }
  return { attachedFiles, attachedImages, images };
}
