import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { Id } from "./_generated/dataModel";

// List non-archived memories for a user
export const listMemories = query({
  args: {
    userId: v.id("users"),
  },
  handler: async (ctx, args) => {
    const memories = await ctx.db
      .query("aiMemories")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .filter((q) => q.eq(q.field("archivedAt"), undefined))
      .collect();

    return memories;
  },
});

// Upsert a memory (create or update by userId + key)
export const upsertMemory = mutation({
  args: {
    userId: v.id("users"),
    type: v.union(
      v.literal("preference"),
      v.literal("constraint"),
      v.literal("injury"),
      v.literal("meta")
    ),
    key: v.string(),
    value: v.string(),
    source: v.union(v.literal("ai"), v.literal("user")),
    expiresAt: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const now = Date.now();

    // Look for existing non-archived memory with same userId and key
    const existingMemory = await ctx.db
      .query("aiMemories")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .filter((q) =>
        q.and(
          q.eq(q.field("key"), args.key),
          q.eq(q.field("archivedAt"), undefined)
        )
      )
      .first();

    if (existingMemory) {
      // Update existing memory
      await ctx.db.patch(existingMemory._id, {
        type: args.type,
        value: args.value,
        source: args.source,
        expiresAt: args.expiresAt,
        updatedAt: now,
      });
      return existingMemory._id;
    } else {
      // Create new memory
      const memoryId = await ctx.db.insert("aiMemories", {
        userId: args.userId,
        type: args.type,
        key: args.key,
        value: args.value,
        source: args.source,
        expiresAt: args.expiresAt,
        createdAt: now,
        updatedAt: now,
      });
      return memoryId;
    }
  },
});

// Archive a memory (soft delete)
export const archiveMemory = mutation({
  args: {
    id: v.id("aiMemories"),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    await ctx.db.patch(args.id, {
      archivedAt: now,
      updatedAt: now,
    });
  },
});
