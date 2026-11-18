import { z } from "zod";
import { IdSchema, MsSchema } from "./common";

/**
 * A log entry: a free note with a time and any number of attached files. No fixed types (ADR-017).
 * The note may be empty when a file is attached. Written only by the app; the AI reads it and never writes it.
 */
export const EntrySchema = z
  .object({
    id: IdSchema,
    text: z.string().max(2000),
    fileIds: z.array(z.string().min(1).max(100)).max(10),
    at: MsSchema,
    createdAt: MsSchema,
  })
  .refine((e) => e.text.trim().length > 0 || e.fileIds.length > 0, { message: "an entry needs a note or a file" })
  .refine((e) => new Set(e.fileIds).size === e.fileIds.length, { message: "fileIds: a file is listed twice" });

export type Entry = z.infer<typeof EntrySchema>;
