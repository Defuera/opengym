import { ConvexError, v } from "convex/values";
import { internal } from "../_generated/api";
import { mutation } from "../_generated/server";
import { requireUser } from "../lib/auth";
import { messageByMessageId, threadByThreadId } from "../lib/db";
import { fileByFileId } from "../lib/files";
import { parseOrThrow } from "../lib/validate";
import { MessageInputSchema } from "../model/schema";
import { MAX_VOICE_BYTES } from "../model/voice";
import { titleFromMessage } from "../model/threadTitle";
import { messageContext } from "../lib/messageFields";
import { applyLogDraft } from "../lib/logDraftDb";
import { applyProposal } from "../lib/proposalDb";
import { truncate } from "../model/rules/util";

const CONTEXT_ID_MAX = 100;

/**
 * Store the user's message at once and start the coach reply in the background.
 * The answer is NOT returned: the app subscribes to queries/messages:list and queries/threads:list
 * (the thread status is `thinking` until the reply is stored). Resending the same messageId changes nothing, except after a failed reply, where it runs the coach again.
 * `context` (optional, ADR-032) says what was open when the person sent it; it is stored on the message. Every message is answered by the coach turn with functions (jobs/coachTurn:run); a message with no screen, or from "start", counts as "chat".
 * `answer` (optional, ADR-032) says the message is a tap on a quick answer of the coach: `turnId` is the `turnId` of the assistant message
 * that asked and `id` the answer. "approve" on a message that holds a whole-session proposal applies it in plain code, with NO AI call, and
 * stores a short fixed reply; on a log draft of the log chat ("Done") it writes the entry and the rows of the draft the same way (lib/logDraftDb.ts)
 * and the reply carries `entryId`; a second approve changes nothing; a proposal that is stale (a newer proposal, another or no open session)
 * is not applied and the reply says why. Any other answer, or no stored proposal, runs the normal coach turn with the text.
 */
export const send = mutation({
  args: { token: v.string(), threadId: v.string(), messageId: v.string(), text: v.string(), fileIds: v.optional(v.array(v.string())), context: v.optional(messageContext), answer: v.optional(v.object({ turnId: v.string(), id: v.string() })) },
  handler: async (ctx, { token, threadId, messageId, text, fileIds, context, answer }) => {
    const userId = await requireUser(ctx, token);
    if (!messageId || messageId.length > 100) throw new ConvexError("messageId: must be 1 to 100 characters");
    for (const [k, id] of Object.entries(context ?? {})) if (k !== "screen" && typeof id === "string" && (id.length < 1 || id.length > CONTEXT_ID_MAX)) throw new ConvexError(`context.${k}: must be 1 to ${CONTEXT_ID_MAX} characters`);
    // The log chat takes a message of files only (ADR-032): its text stays empty. Every other message needs a text.
    const filesOnly = context?.screen === "log" && !text.trim() && (fileIds?.length ?? 0) > 0;
    const valid = filesOnly ? { ...parseOrThrow(MessageInputSchema, { text: "-", fileIds }, "message"), text: "" } : parseOrThrow(MessageInputSchema, { text, fileIds }, "message");
    const thread = await threadByThreadId(ctx, userId, threadId);
    if (!thread) throw new ConvexError(`thread not found: ${threadId}`);
    if (answer && (answer.turnId.length < 1 || answer.turnId.length > CONTEXT_ID_MAX || answer.id.length < 1 || answer.id.length > 40)) throw new ConvexError("answer: turnId must be 1 to 100 and id 1 to 40 characters");
    const now = Date.now();
    const stored = await messageByMessageId(ctx, userId, messageId);
    if (stored) {
      if (stored.voice !== undefined && stored.voice !== "done") return messageId; // a voice message waits for its transcript (retryVoice); no coach run yet
      // A resend after a failed coach reply is a retry: run the coach again for the stored message.
      // Only if no assistant message came after it, so an answered message never gets a second answer.
      const answered = stored.role !== "user" || (await ctx.db.query("messages").withIndex("by_threadId", (q) => q.eq("threadId", threadId).gt("_creationTime", stored._creationTime)).filter((q) => q.eq(q.field("role"), "assistant")).first());
      if (thread.status === "failed" && !answered) {
        await ctx.db.patch(thread._id, { status: "thinking", error: undefined, pending: thread.pending + 1, updatedAt: now });
        await ctx.scheduler.runAfter(0, internal.jobs.coachTurn.run, { userId, threadId, messageId });
      }
      return messageId;
    }
    // The person approves a whole-session proposal: plain code applies it. No AI call, no pending reply.
    if (answer?.id === "approve") {
      const asked = await ctx.db.query("messages").withIndex("by_turnId", (q) => q.eq("turnId", answer.turnId)).first();
      if (asked?.proposal && asked.threadId === threadId && asked.role === "assistant") {
        await ctx.db.insert("messages", { userId, messageId, threadId, role: "user", text: valid.text, fileIds: valid.fileIds ?? [], sources: [], ...(context ? { context } : {}), answer, createdAt: now });
        if (asked.proposal.type === "log") {
          // "Done" on a log draft (ADR-032): the entry and the rows of the draft are written in this transaction, by plain code.
          const done = await applyLogDraft(ctx, userId, asked);
          const logAction = { actionId: "approve", name: "draft_log", status: done.status === "refused" ? ("rejected" as const) : ("applied" as const), ...(done.reason ? { reason: done.reason } : {}) };
          await ctx.db.insert("messages", { userId, messageId: crypto.randomUUID(), threadId, role: "assistant", text: done.text, fileIds: [], sources: [], turnId: messageId, actions: [logAction], ...(done.entryId ? { entryId: done.entryId } : {}), createdAt: now + 1 });
          await ctx.db.patch(thread._id, { updatedAt: now + 1, lastMessage: truncate(done.text, 200) });
          return messageId;
        }
        const out = await applyProposal(ctx, userId, asked);
        const action = { actionId: "approve", name: "rebuild_open_session", status: out.status === "refused" ? ("rejected" as const) : ("applied" as const), ...(out.reason ? { reason: out.reason } : {}) };
        await ctx.db.insert("messages", { userId, messageId: crypto.randomUUID(), threadId, role: "assistant", text: out.text, fileIds: [], sources: [], turnId: messageId, actions: [action], createdAt: now + 1 });
        await ctx.db.patch(thread._id, { updatedAt: now + 1, lastMessage: truncate(out.text, 200) });
        return messageId;
      }
    }
    // First user message of a thread the user has not named: name it now by plain code. The coach job may improve it later.
    const first = !(await ctx.db.query("messages").withIndex("by_threadId", (q) => q.eq("threadId", threadId)).filter((q) => q.eq(q.field("role"), "user")).first());
    const title = thread.titleSource === "auto" && first && !thread.about ? { title: titleFromMessage(valid.text) } : {};
    await ctx.db.insert("messages", { userId, messageId, threadId, role: "user", text: valid.text, fileIds: valid.fileIds ?? [], sources: [], ...(context ? { context } : {}), ...(answer ? { answer } : {}), createdAt: now });
    const session = first && context?.openSessionId !== undefined && thread.openSessionId === undefined ? { openSessionId: context.openSessionId } : {};
    await ctx.db.patch(thread._id, { ...title, ...session, status: "thinking", error: undefined, pending: thread.pending + 1, updatedAt: now });
    await ctx.scheduler.runAfter(0, internal.jobs.coachTurn.run, { userId, threadId, messageId });
    return messageId;
  },
});

/**
 * A voice message: the audio is already uploaded (commands/files:register, kind "audio"). Stores a user message with an empty
 * text and `voice: "pending"`, counts one pending reply like `send`, and schedules the transcription (jobs/voice:transcribe).
 * `context` is the screen data of a typed message (ADR-032): a voice message carries the same. The coach reply is scheduled by the job once the transcript is stored. Resending the same messageId changes nothing.
 */
export const sendVoice = mutation({
  args: { token: v.string(), threadId: v.string(), messageId: v.string(), fileId: v.string(), context: v.optional(messageContext) },
  handler: async (ctx, { token, threadId, messageId, fileId, context }) => {
    const userId = await requireUser(ctx, token);
    if (!messageId || messageId.length > 100) throw new ConvexError("messageId: must be 1 to 100 characters");
    for (const [k, id] of Object.entries(context ?? {})) if (k !== "screen" && typeof id === "string" && (id.length < 1 || id.length > CONTEXT_ID_MAX)) throw new ConvexError(`context.${k}: must be 1 to ${CONTEXT_ID_MAX} characters`);
    const thread = await threadByThreadId(ctx, userId, threadId);
    if (!thread) throw new ConvexError(`thread not found: ${threadId}`);
    if (await messageByMessageId(ctx, userId, messageId)) return messageId;
    const file = await fileByFileId(ctx, userId, fileId);
    if (!file) throw new ConvexError(`file not found: ${fileId}`);
    if (file.kind !== "audio") throw new ConvexError("fileId: the file is not audio");
    if (file.size > MAX_VOICE_BYTES) throw new ConvexError("fileId: the recording is larger than 10 MB");
    const now = Date.now();
    await ctx.db.insert("messages", { userId, messageId, threadId, role: "user", text: "", fileIds: [fileId], sources: [], voice: "pending", ...(context ? { context } : {}), createdAt: now });
    await ctx.db.patch(thread._id, { status: "thinking", error: undefined, pending: thread.pending + 1, updatedAt: now });
    await ctx.scheduler.runAfter(0, internal.jobs.voice.transcribe, { userId, messageId });
    return messageId;
  },
});

/** Runs the transcription again for a voice message whose transcript failed. Returns false for any other message. */
export const retryVoice = mutation({
  args: { token: v.string(), messageId: v.string() },
  handler: async (ctx, { token, messageId }): Promise<boolean> => {
    const userId = await requireUser(ctx, token);
    const m = await messageByMessageId(ctx, userId, messageId);
    if (!m || m.role !== "user" || m.voice !== "failed") return false;
    const thread = await threadByThreadId(ctx, userId, m.threadId);
    if (!thread) return false;
    await ctx.db.patch(m._id, { voice: "pending" });
    await ctx.db.patch(thread._id, { status: "thinking", error: undefined, pending: thread.pending + 1, updatedAt: Date.now() });
    await ctx.scheduler.runAfter(0, internal.jobs.voice.transcribe, { userId, messageId });
    return true;
  },
});
