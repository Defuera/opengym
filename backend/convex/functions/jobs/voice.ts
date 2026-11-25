import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { messageByMessageId, threadByThreadId } from "../lib/db";
import { fileByFileId } from "../lib/files";
import { transcribeFile } from "../lib/transcribe";
import { MESSAGE_MAX_CHARS } from "../model/schema";
import { titleFromMessage } from "../model/threadTitle";

/** What the transcription needs: the file of a voice message that still waits. Null when there is nothing to do. */
export const input = internalQuery({
  args: { messageId: v.string() },
  handler: async (ctx, { messageId }) => {
    const m = await messageByMessageId(ctx, messageId);
    if (!m || m.role !== "user" || m.voice !== "pending") return null;
    const f = m.fileIds[0] ? await fileByFileId(ctx, m.fileIds[0]) : null;
    return { file: f ? { fileId: f.fileId, storageId: f.storageId, name: f.name, mime: f.mime, size: f.size, kind: f.kind, createdAt: f.createdAt } : null };
  },
});

/**
 * Stores the transcript and starts the coach exactly like `commands/messages:send` does for a typed message.
 * The pending count was raised by sendVoice, so it is not raised again. False when the message is no longer pending
 * (a second run), so the reply is never scheduled twice.
 */
export const saveTranscript = internalMutation({
  args: { messageId: v.string(), text: v.string() },
  handler: async (ctx, { messageId, text }): Promise<boolean> => {
    const m = await messageByMessageId(ctx, messageId);
    if (!m || m.voice !== "pending") return false;
    const thread = await threadByThreadId(ctx, m.threadId);
    if (!thread) return false;
    const clean = text.trim().slice(0, MESSAGE_MAX_CHARS);
    await ctx.db.patch(m._id, { text: clean, voice: "done" });
    // Same as send: name an unnamed thread from its first user message.
    const firstUser = await ctx.db.query("messages").withIndex("by_threadId", (q) => q.eq("threadId", m.threadId)).filter((q) => q.eq(q.field("role"), "user")).first();
    const title = thread.titleSource === "auto" && !thread.about && firstUser?.messageId === messageId ? { title: titleFromMessage(clean) } : {};
    await ctx.db.patch(thread._id, { ...title, updatedAt: Date.now() });
    await ctx.scheduler.runAfter(0, internal.jobs.coachTurn.run, { threadId: m.threadId, messageId });
    return true;
  },
});

/** The transcript failed: mark the message and give back its pending count. No coach reply. */
export const saveFailure = internalMutation({
  args: { messageId: v.string() },
  handler: async (ctx, { messageId }) => {
    const m = await messageByMessageId(ctx, messageId);
    if (!m || m.voice !== "pending") return;
    await ctx.db.patch(m._id, { voice: "failed" });
    const thread = await threadByThreadId(ctx, m.threadId);
    if (!thread) return;
    const pending = Math.max(0, thread.pending - 1);
    await ctx.db.patch(thread._id, { pending, status: pending > 0 ? "thinking" : "idle", updatedAt: Date.now() });
  },
});

/** Speech to text for one voice message (scheduled by commands/messages:sendVoice and retryVoice). Logs only a short reduced text, never a provider message. */
export const transcribe = internalAction({
  args: { messageId: v.string() },
  handler: async (ctx, { messageId }): Promise<void> => {
    const data = await ctx.runQuery(internal.jobs.voice.input, { messageId });
    if (!data) return;
    const out = await transcribeFile(ctx, data.file);
    if (out.ok) return void (await ctx.runMutation(internal.jobs.voice.saveTranscript, { messageId, text: out.text }));
    console.error(`[voice] transcription failed: ${out.why}`);
    await ctx.runMutation(internal.jobs.voice.saveFailure, { messageId });
  },
});

/** The file of an audio recording that is no part of a message yet (commands/voice:transcribe). Null when unknown or not audio. */
export const audioFile = internalQuery({
  args: { fileId: v.string() },
  handler: async (ctx, { fileId }) => {
    const f = await fileByFileId(ctx, fileId);
    return f && f.kind === "audio" ? { fileId: f.fileId, storageId: f.storageId, name: f.name, mime: f.mime, size: f.size, kind: f.kind, createdAt: f.createdAt } : null;
  },
});

/** Removes a temporary recording (storage blob and files row) once its text was handed to the app. */
export const dropAudio = internalMutation({
  args: { fileId: v.string() },
  handler: async (ctx, { fileId }) => {
    const f = await fileByFileId(ctx, fileId);
    if (!f || f.kind !== "audio") return;
    await ctx.storage.delete(f.storageId);
    await ctx.db.delete(f._id);
  },
});
