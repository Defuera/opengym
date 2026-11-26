import { ConvexError, v } from "convex/values";
import { mutation } from "../_generated/server";
import { requireUser } from "../lib/auth";
import { deleteThreadWithMessages, threadByThreadId } from "../lib/db";
import { threadAbout } from "../lib/programFields";
import { programByProgramId } from "../lib/programsDb";
import { parseOrThrow } from "../lib/validate";
import { ThreadInputSchema, ThreadRenameSchema } from "../model/schema";
import { NEW_CHAT_TITLE, NEW_PROGRAM_TITLE } from "../model/threadTitle";

/**
 * Create a thread with a client-made threadId. Resending the same threadId changes nothing.
 * No title needed: the thread starts as "New chat" (titleSource "auto") and is named after the first message.
 * A given title counts as set by the user.
 * `placeId` (optional, 1..100, ADR-021): the conversation is about that place. The coach reads the place and learns from the
 * user's messages here. Stored as given; ignored on a resend (the thread exists).
 * `about` (optional, ADR-026): what the conversation is about, `{ kind: "program", id? }`. With an `id` (1..100) the program must exist. Without
 * a title the thread is called "New program" or by the program's title (titleSource "auto"); no automatic title job runs for it. Stored as
 * given; ignored on a resend.
 */
export const create = mutation({
  args: { token: v.string(), threadId: v.string(), title: v.optional(v.string()), placeId: v.optional(v.string()), about: v.optional(threadAbout) },
  handler: async (ctx, { token, threadId, title, placeId, about }) => {
    const userId = await requireUser(ctx, token);
    if (!threadId || threadId.length > 100) throw new ConvexError("threadId: must be 1 to 100 characters");
    const valid = parseOrThrow(ThreadInputSchema, { title }, "thread");
    if (placeId !== undefined && (placeId.length < 1 || placeId.length > 100)) throw new ConvexError("placeId: must be 1 to 100 characters");
    if (about?.id !== undefined && (about.id.length < 1 || about.id.length > 100)) throw new ConvexError("about.id: must be 1 to 100 characters");
    if (await threadByThreadId(ctx, userId, threadId)) return threadId;
    const program = about?.id !== undefined ? await programByProgramId(ctx, userId, about.id) : null;
    if (about?.id !== undefined && !program) throw new ConvexError("program not found");
    const auto = about ? (program ? program.title : NEW_PROGRAM_TITLE) : NEW_CHAT_TITLE;
    const now = Date.now();
    await ctx.db.insert("threads", { userId, threadId, title: valid.title ?? auto, titleSource: valid.title ? "user" : "auto", createdAt: now, updatedAt: now, summary: "", status: "idle", pending: 0, ...(placeId !== undefined ? { placeId } : {}), ...(about ? { about } : {}) });
    return threadId;
  },
});

/** The user renames a thread. The title is then "user": no automatic title replaces it. Returns false if unknown. */
export const rename = mutation({
  args: { token: v.string(), threadId: v.string(), title: v.string() },
  handler: async (ctx, { token, threadId, title }) => {
    const userId = await requireUser(ctx, token);
    const valid = parseOrThrow(ThreadRenameSchema, { title }, "thread");
    const thread = await threadByThreadId(ctx, userId, threadId);
    if (!thread) return false;
    await ctx.db.patch(thread._id, { title: valid.title, titleSource: "user" });
    return true;
  },
});

/** Delete a thread and its messages. Goals and context items it produced stay (they are facts now). Returns false if unknown. */
export const remove = mutation({
  args: { token: v.string(), threadId: v.string() },
  handler: async (ctx, { token, threadId }) => {
    const userId = await requireUser(ctx, token);
    const thread = await threadByThreadId(ctx, userId, threadId);
    if (!thread) return false;
    await deleteThreadWithMessages(ctx, userId, thread);
    return true;
  },
});
