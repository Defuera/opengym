import { v } from "convex/values";
import { query, action } from "./_generated/server";
import { api, internal } from "./_generated/api";
import { Id } from "./_generated/dataModel";
import { executeWriteTool } from "./aiCoachTools";

export const listByThread = query({
  args: { threadId: v.id("aiThreads") },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("aiActions")
      .withIndex("by_thread", (q) => q.eq("threadId", args.threadId))
      .collect();
  },
});

export const listByMessage = query({
  args: { messageId: v.id("aiMessages") },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("aiActions")
      .withIndex("by_message", (q) => q.eq("messageId", args.messageId))
      .collect();
  },
});

export const confirmAction = action({
  args: { actionId: v.id("aiActions") },
  handler: async (ctx, args) => {
    const actionDoc: any = await ctx.runQuery(
      internal.aiActions_internal.getAction,
      { actionId: args.actionId }
    );
    if (!actionDoc || actionDoc.status !== "pending") {
      throw new Error("Action not found or already resolved");
    }

    // Resolve the user
    const userId: Id<"users"> = await ctx.runMutation(
      api.users.getOrCreateDefaultUser,
      {}
    );

    const toolArgs = JSON.parse(actionDoc.toolArgs);
    let result: unknown;
    try {
      result = await executeWriteTool(
        ctx as any,
        userId,
        actionDoc.toolName,
        toolArgs
      );
    } catch (err) {
      result = { error: err instanceof Error ? err.message : String(err) };
    }

    await ctx.runMutation(internal.aiActions_internal.resolveAction, {
      actionId: args.actionId,
      status: "confirmed",
      result: JSON.stringify(result),
    });

    return result;
  },
});

export const rejectAction = action({
  args: { actionId: v.id("aiActions") },
  handler: async (ctx, args) => {
    const actionDoc: any = await ctx.runQuery(
      internal.aiActions_internal.getAction,
      { actionId: args.actionId }
    );
    if (!actionDoc || actionDoc.status !== "pending") {
      throw new Error("Action not found or already resolved");
    }

    await ctx.runMutation(internal.aiActions_internal.resolveAction, {
      actionId: args.actionId,
      status: "rejected",
      result: JSON.stringify({ rejected: true }),
    });
  },
});
