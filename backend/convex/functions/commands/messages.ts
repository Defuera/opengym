import { ConvexError, v } from "convex/values";
import { internal } from "../_generated/api";
import { mutation } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { messageByMessageId, threadByThreadId } from "../lib/db";
import { fileByFileId } from "../lib/files";
import { parseOrThrow } from "../lib/validate";
import { MessageInputSchema } from "../model/schema";
import { MAX_VOICE_BYTES } from "../model/voice";
import { titleFromMessage } from "../model/threadTitle";

/**
 * Store the user's message at once and start the coach reply in the background.
 * The answer is NOT returned: the app subscribes to queries/messages:list and queries/threads:list
 * (the thread status is `thinking` until the reply is stored). Resending the same messageId changes nothing, except after a failed reply, where it runs the coach again.
 */
export const send = mutation({
  args: { token: v.string(), threadId: v.string(), messageId: v.string(), text: v.string(), fileIds: v.optional(v.array(v.string())) },
  handler: async (ctx, { token, threadId, messageId, text, fileIds }) => {
    requireToken(token);
    if (!messageId || messageId.length > 100) throw new ConvexError("messageId: must be 1 to 100 characters");
    const valid = parseOrThrow(MessageInputSchema, { text, fileIds }, "message");
    const thread = await threadByThreadId(ctx, threadId);
    if (!thread) throw new ConvexError(`thread not found: ${threadId}`);
    const now = Date.now();
    const stored = await messageByMessageId(ctx, messageId);
    if (stored) {
      if (stored.voice !== undefined && stored.voice !== "done") return messageId; // a voice message waits for its transcript (retryVoice); no coach run yet
      // A resend after a failed coach reply is a retry: run the coach again for the stored message.
      // Only if no assistant message came after it, so an answered message never gets a second answer.
      const answered = stored.role !== "user" || (await ctx.db.query("messages").withIndex("by_threadId", (q) => q.eq("threadId", threadId).gt("_creationTime", stored._creationTime)).filter((q) => q.eq(q.field("role"), "assistant")).first());
      if (thread.status === "failed" && !answered) {
        await ctx.db.patch(thread._id, { status: "thinking", error: undefined, pending: thread.pending + 1, updatedAt: now });
        await ctx.scheduler.runAfter(0, internal.jobs.chat.reply, { threadId, messageId });
      }
      return messageId;
    }
    // First user message of a thread the user has not named: name it now by plain code. The coach job may improve it later.
    const first = !(await ctx.db.query("messages").withIndex("by_threadId", (q) => q.eq("threadId", threadId)).filter((q) => q.eq(q.field("role"), "user")).first());
    const title = thread.titleSource === "auto" && first ? { title: titleFromMessage(valid.text) } : {};
    await ctx.db.insert("messages", { messageId, threadId, role: "user", text: valid.text, fileIds: valid.fileIds ?? [], sources: [], createdAt: now });
    await ctx.db.patch(thread._id, { ...title, status: "thinking", error: undefined, pending: thread.pending + 1, updatedAt: now });
    await ctx.scheduler.runAfter(0, internal.jobs.chat.reply, { threadId, messageId });
    // A thread about a place (ADR-021): the background job may learn from what the user says. It never blocks the reply.
    if (thread.placeId !== undefined) await ctx.scheduler.runAfter(0, internal.jobs.places.learn, { placeId: thread.placeId, source: "chat", sentence: valid.text, ...(valid.fileIds?.length ? { fileIds: valid.fileIds } : {}) });
    return messageId;
  },
});

/**
 * A voice message: the audio is already uploaded (commands/files:register, kind "audio"). Stores a user message with an empty
 * text and `voice: "pending"`, counts one pending reply like `send`, and schedules the transcription (jobs/voice:transcribe).
 * The coach reply is scheduled by the job once the transcript is stored. Resending the same messageId changes nothing.
 */
export const sendVoice = mutation({
  args: { token: v.string(), threadId: v.string(), messageId: v.string(), fileId: v.string() },
  handler: async (ctx, { token, threadId, messageId, fileId }) => {
    requireToken(token);
    if (!messageId || messageId.length > 100) throw new ConvexError("messageId: must be 1 to 100 characters");
    const thread = await threadByThreadId(ctx, threadId);
    if (!thread) throw new ConvexError(`thread not found: ${threadId}`);
    if (await messageByMessageId(ctx, messageId)) return messageId;
    const file = await fileByFileId(ctx, fileId);
    if (!file) throw new ConvexError(`file not found: ${fileId}`);
    if (file.kind !== "audio") throw new ConvexError("fileId: the file is not audio");
    if (file.size > MAX_VOICE_BYTES) throw new ConvexError("fileId: the recording is larger than 10 MB");
    const now = Date.now();
    await ctx.db.insert("messages", { messageId, threadId, role: "user", text: "", fileIds: [fileId], sources: [], voice: "pending", createdAt: now });
    await ctx.db.patch(thread._id, { status: "thinking", error: undefined, pending: thread.pending + 1, updatedAt: now });
    await ctx.scheduler.runAfter(0, internal.jobs.voice.transcribe, { messageId });
    return messageId;
  },
});

/** Runs the transcription again for a voice message whose transcript failed. Returns false for any other message. */
export const retryVoice = mutation({
  args: { token: v.string(), messageId: v.string() },
  handler: async (ctx, { token, messageId }): Promise<boolean> => {
    requireToken(token);
    const m = await messageByMessageId(ctx, messageId);
    if (!m || m.role !== "user" || m.voice !== "failed") return false;
    const thread = await threadByThreadId(ctx, m.threadId);
    if (!thread) return false;
    await ctx.db.patch(m._id, { voice: "pending" });
    await ctx.db.patch(thread._id, { status: "thinking", error: undefined, pending: thread.pending + 1, updatedAt: Date.now() });
    await ctx.scheduler.runAfter(0, internal.jobs.voice.transcribe, { messageId });
    return true;
  },
});
