import { ConvexError, v } from "convex/values";
import { mutation } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { threadByThreadId } from "../lib/db";
import { parseOrThrow } from "../lib/validate";
import { ThreadInputSchema } from "../model/schema";

/** Create a thread with a client-made threadId. Resending the same threadId changes nothing. */
export const create = mutation({
  args: { token: v.string(), threadId: v.string(), title: v.string() },
  handler: async (ctx, { token, threadId, title }) => {
    requireToken(token);
    if (!threadId || threadId.length > 100) throw new ConvexError("threadId: must be 1 to 100 characters");
    const valid = parseOrThrow(ThreadInputSchema, { title }, "thread");
    if (await threadByThreadId(ctx, threadId)) return threadId;
    const now = Date.now();
    await ctx.db.insert("threads", { threadId, title: valid.title, createdAt: now, updatedAt: now, summary: "", status: "idle", pending: 0 });
    return threadId;
  },
});

/** Delete a thread and its messages. Goals and context items it produced stay (they are facts now). Returns false if unknown. */
export const remove = mutation({
  args: { token: v.string(), threadId: v.string() },
  handler: async (ctx, { token, threadId }) => {
    requireToken(token);
    const thread = await threadByThreadId(ctx, threadId);
    if (!thread) return false;
    for (const m of await ctx.db.query("messages").withIndex("by_threadId", (q) => q.eq("threadId", threadId)).collect()) await ctx.db.delete(m._id);
    await ctx.db.delete(thread._id);
    return true;
  },
});
