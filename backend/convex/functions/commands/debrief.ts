import { ConvexError, v } from "convex/values";
import { mutation } from "../_generated/server";
import { requireUser } from "../lib/auth";
import { debriefMessageId, debriefThreadId } from "../lib/debriefDb";
import { sessionBySessionId, threadByThreadId } from "../lib/db";
import { truncate } from "../model/rules/util";

/**
 * Opens the debrief chat of a finished session (ADR-041). The chat is the one coach chat; this is the thread about that session:
 * its first message is the coach's debrief (the `message` of the stored review, with its `question` and quick answers), written by plain code.
 * The person then answers with the normal `commands/messages:send` (a tap on an answer sends its label as the text), and the normal coach turn replies.
 * Idempotent: the thread id is made from the session id, so a second call (a second tap, a retry) finds the thread and changes nothing.
 * Returns `{ threadId }`. Throws when the session is unknown or marked as deleted, or when it has no new-style review (an old review with only a summary opens no chat).
 */
export const open = mutation({
  args: { token: v.string(), sessionId: v.string() },
  handler: async (ctx, { token, sessionId }) => {
    const userId = await requireUser(ctx, token);
    if (!sessionId || sessionId.length > 100) throw new ConvexError("sessionId: must be 1 to 100 characters");
    const session = await sessionBySessionId(ctx, userId, sessionId);
    if (!session) throw new ConvexError(`session not found: ${sessionId}`);
    const threadId = debriefThreadId(sessionId);
    if (await threadByThreadId(ctx, userId, threadId)) return { threadId };
    const review = await ctx.db.query("reviews").withIndex("by_user_and_sessionId", (q) => q.eq("userId", userId).eq("sessionId", sessionId)).unique();
    if (!review?.message) throw new ConvexError("this session has no debrief");
    const now = Date.now();
    const label = session.focus ? `${session.type} ${session.focus}` : session.type;
    await ctx.db.insert("threads", { userId, threadId, title: truncate(`Debrief: ${label}`, 60), titleSource: "user", createdAt: now, updatedAt: now, summary: "", lastMessage: truncate(review.message, 200), status: "idle", pending: 0, debriefOf: sessionId });
    await ctx.db.insert("messages", { userId, messageId: debriefMessageId(sessionId), threadId, role: "assistant", text: review.message, fileIds: [], sources: [], ...(review.question ? { question: review.question } : {}), createdAt: now });
    return { threadId };
  },
});
