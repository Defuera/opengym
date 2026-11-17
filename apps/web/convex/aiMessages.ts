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
  args: {
    messageId: v.id("aiMessages"),
    branchId: v.optional(v.string()),
  },
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
      const patch: { deletedAt: number; branchId?: string } = { deletedAt: now };
      if (args.branchId) {
        patch.branchId = args.branchId;
      }
      await ctx.db.patch(msg._id, patch);

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

export const listBranches = query({
  args: { threadId: v.id("aiThreads") },
  handler: async (ctx, args) => {
    const messages = await ctx.db
      .query("aiMessages")
      .withIndex("by_thread", (q) => q.eq("threadId", args.threadId))
      .collect();

    const branchMap = new Map<
      string,
      { branchId: string; createdAt: number; messageCount: number }
    >();

    for (const msg of messages) {
      if (!msg.branchId) continue;
      const existing = branchMap.get(msg.branchId);
      if (existing) {
        existing.messageCount++;
        if (msg.createdAt < existing.createdAt) {
          existing.createdAt = msg.createdAt;
        }
      } else {
        branchMap.set(msg.branchId, {
          branchId: msg.branchId,
          createdAt: msg.createdAt,
          messageCount: 1,
        });
      }
    }

    return Array.from(branchMap.values()).sort(
      (a, b) => b.createdAt - a.createdAt
    );
  },
});

export const listBranchMessages = query({
  args: {
    threadId: v.id("aiThreads"),
    branchId: v.string(),
  },
  handler: async (ctx, args) => {
    const messages = await ctx.db
      .query("aiMessages")
      .withIndex("by_thread", (q) => q.eq("threadId", args.threadId))
      .collect();

    return messages
      .filter((m) => m.branchId === args.branchId)
      .sort((a, b) => a.createdAt - b.createdAt);
  },
});
