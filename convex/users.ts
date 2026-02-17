import { v } from "convex/values";
import { mutation, query } from "./_generated/server";

// Get a user by ID
export const get = query({
  args: { id: v.id("users") },
  handler: async (ctx, args) => {
    return await ctx.db.get(args.id);
  },
});

// Create a new user
export const create = mutation({
  args: {
    name: v.string(),
  },
  handler: async (ctx, args) => {
    const userId = await ctx.db.insert("users", {
      name: args.name,
      createdAt: Date.now(),
    });
    return userId;
  },
});
