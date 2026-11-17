import { z } from "zod";
import { IdSchema, MsSchema } from "./common";

export const ThreadSchema = z.object({
  id: IdSchema,
  title: z.string().min(1).max(60),
  titleSource: z.enum(["auto", "user"]),
  createdAt: MsSchema,
  updatedAt: MsSchema,
  summary: z.string(),
  lastMessage: z.string().optional(),
});

/** A title the user typed (create with a title, or rename). */
export const ThreadTitleSchema = z.string().trim().min(1).max(60);
export const ThreadInputSchema = z.object({ title: ThreadTitleSchema.optional() });
export const ThreadRenameSchema = z.object({ title: ThreadTitleSchema });

export const MessageSchema = z.object({
  id: IdSchema,
  threadId: IdSchema,
  role: z.enum(["user", "assistant"]),
  text: z.string(),
  fileIds: z.array(z.string()),
  sources: z.array(z.string()),
  createdAt: MsSchema,
});

export const MessageInputSchema = z.object({
  text: z.string().min(1).max(8000),
  fileIds: z.array(z.string()).max(10).optional(),
});

export const FileMetaSchema = z.object({
  id: IdSchema,
  name: z.string(),
  mime: z.string(),
  size: z.number().int().nonnegative(),
  kind: z.enum(["text", "image", "pdf", "audio", "other"]),
  createdAt: MsSchema,
});

export type Thread = z.infer<typeof ThreadSchema>;
export type Message = z.infer<typeof MessageSchema>;
export type FileMeta = z.infer<typeof FileMetaSchema>;
