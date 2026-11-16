import { v } from "convex/values";
import { internalQuery, internalMutation } from "./_generated/server";

export const getAction = internalQuery({
  args: { actionId: v.id("aiActions") },
  handler: async (ctx, args) => {
    return await ctx.db.get(args.actionId);
  },
});

export const resolveAction = internalMutation({
  args: {
    actionId: v.id("aiActions"),
    status: v.union(v.literal("confirmed"), v.literal("rejected")),
    result: v.string(),
  },
  handler: async (ctx, args) => {
    await ctx.db.patch(args.actionId, {
      status: args.status,
      result: args.result,
      resolvedAt: Date.now(),
    });
  },
});

export const createAction = internalMutation({
  args: {
    messageId: v.id("aiMessages"),
    threadId: v.id("aiThreads"),
    toolCallId: v.string(),
    toolName: v.string(),
    toolArgs: v.string(),
    description: v.string(),
  },
  handler: async (ctx, args) => {
    return await ctx.db.insert("aiActions", {
      messageId: args.messageId,
      threadId: args.threadId,
      toolCallId: args.toolCallId,
      toolName: args.toolName,
      toolArgs: args.toolArgs,
      description: args.description,
      status: "pending",
      createdAt: Date.now(),
    });
  },
});
