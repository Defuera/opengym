import { v } from "convex/values";
import { query, mutation, internalMutation } from "./_generated/server";

export const listMessages = query({
  args: { threadId: v.id("aiThreads") },
  handler: async (ctx, args) => {
    const messages = await ctx.db
      .query("aiMessages")
      .withIndex("by_thread", (q) => q.eq("threadId", args.threadId))
      .collect();

    return messages
      .filter((m) => !m.deletedAt)
      .sort((a, b) => a.createdAt - b.createdAt);
  },
});

export const saveMessage = internalMutation({
  args: {
    threadId: v.id("aiThreads"),
    role: v.union(v.literal("user"), v.literal("assistant")),
    content: v.string(),
    toolCalls: v.optional(
      v.array(
        v.object({
          id: v.string(),
          name: v.string(),
          arguments: v.string(),
        })
      )
    ),
    model: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    const messageId = await ctx.db.insert("aiMessages", {
      threadId: args.threadId,
      role: args.role,
      content: args.content,
      toolCalls: args.toolCalls,
      model: args.model,
      createdAt: now,
    });
    await ctx.db.patch(args.threadId, { updatedAt: now });
    return messageId;
  },
});

export const softDeleteFrom = mutation({
  args: { messageId: v.id("aiMessages") },
  handler: async (ctx, args) => {
    const target = await ctx.db.get(args.messageId);
    if (!target || target.deletedAt) return;

    const now = Date.now();

    // Get all messages in this thread after (and including) the target
    const allMessages = await ctx.db
      .query("aiMessages")
      .withIndex("by_thread", (q) => q.eq("threadId", target.threadId))
      .collect();

    const toDelete = allMessages.filter(
      (m) => !m.deletedAt && m.createdAt >= target.createdAt
    );

    for (const msg of toDelete) {
      await ctx.db.patch(msg._id, { deletedAt: now });

      // Auto-reject any pending actions on deleted messages
      const actions = await ctx.db
        .query("aiActions")
        .withIndex("by_message", (q) => q.eq("messageId", msg._id))
        .collect();

      for (const action of actions) {
        if (action.status === "pending") {
          await ctx.db.patch(action._id, {
            status: "rejected",
            resolvedAt: now,
          });
        }
      }
    }
  },
});
