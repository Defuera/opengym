import { v } from "convex/values";
import { query, mutation } from "./_generated/server";

export const listThreads = query({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const threads = await ctx.db
      .query("aiThreads")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .collect();

    return threads
      .filter((t) => !t.archivedAt)
      .sort((a, b) => b.updatedAt - a.updatedAt);
  },
});

export const getOrCreateThread = mutation({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const threads = await ctx.db
      .query("aiThreads")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .collect();

    const active = threads
      .filter((t) => !t.archivedAt)
      .sort((a, b) => b.updatedAt - a.updatedAt);

    if (active.length > 0) {
      return active[0]._id;
    }

    const now = Date.now();
    return await ctx.db.insert("aiThreads", {
      userId: args.userId,
      createdAt: now,
      updatedAt: now,
    });
  },
});

export const createThread = mutation({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const now = Date.now();
    return await ctx.db.insert("aiThreads", {
      userId: args.userId,
      createdAt: now,
      updatedAt: now,
    });
  },
});

export const archiveThread = mutation({
  args: { threadId: v.id("aiThreads") },
  handler: async (ctx, args) => {
    await ctx.db.patch(args.threadId, { archivedAt: Date.now() });
  },
});

export const updateThreadTitle = mutation({
  args: { threadId: v.id("aiThreads"), title: v.string() },
  handler: async (ctx, args) => {
    await ctx.db.patch(args.threadId, { title: args.title });
  },
});
