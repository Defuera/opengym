import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { providerFor } from "../lib/ai";
import { messageByMessageId, threadByThreadId } from "../lib/db";
import { fileByFileId, fileBytes } from "../lib/files";
import { MESSAGE_MAX_CHARS } from "../model/schema";
import { titleFromMessage } from "../model/threadTitle";
import { listError } from "./models";

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
    await ctx.scheduler.runAfter(0, internal.jobs.chat.reply, { threadId: m.threadId, messageId });
    if (thread.placeId !== undefined) await ctx.scheduler.runAfter(0, internal.jobs.places.learn, { placeId: thread.placeId, source: "chat", sentence: clean });
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
    const fail = async (why: string) => {
      console.error(`[voice] transcription failed: ${why}`);
      await ctx.runMutation(internal.jobs.voice.saveFailure, { messageId });
    };
    try {
      const provider = await providerFor(ctx);
      if (!provider?.transcribe) return await fail("the AI provider cannot transcribe");
      const bytes = data.file ? await fileBytes(ctx, data.file) : null;
      if (!bytes) return await fail("the recording is gone");
      const text = (await provider.transcribe(bytes, data.file!.mime, data.file!.name)).trim();
      if (!text) return await fail("empty transcript");
      await ctx.runMutation(internal.jobs.voice.saveTranscript, { messageId, text });
    } catch (e) {
      await fail(listError(e));
    }
  },
});
