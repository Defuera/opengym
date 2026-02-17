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

// Get or create the default user (for development/testing)
export const getOrCreateDefaultUser = mutation({
  args: {},
  handler: async (ctx, args) => {
    // Look for a user named "Default User"
    const users = await ctx.db.query("users").collect();
    const defaultUser = users.find((u) => u.name === "Default User");

    if (defaultUser) {
      return defaultUser._id;
    }

    // Create default user if it doesn't exist
    const userId = await ctx.db.insert("users", {
      name: "Default User",
      createdAt: Date.now(),
    });

    return userId;
  },
});
