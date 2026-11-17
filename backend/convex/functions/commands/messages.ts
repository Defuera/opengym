import { ConvexError, v } from "convex/values";
import { internal } from "../_generated/api";
import { mutation } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { messageByMessageId, threadByThreadId } from "../lib/db";
import { parseOrThrow } from "../lib/validate";
import { MessageInputSchema } from "../model/schema";
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
    return messageId;
  },
});
