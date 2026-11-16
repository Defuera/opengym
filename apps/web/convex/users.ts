import { v } from "convex/values";
import { mutation, query } from "./_generated/server";

// Get a user by ID
export const get = query({
  args: { id: v.id("users") },
  handler: async (ctx, args) => {
    return await ctx.db.get(args.id);
  },
});

// Get the default user (for development/testing)
export const getDefaultUser = query({
  args: {},
  handler: async (ctx) => {
    const users = await ctx.db.query("users").collect();
    return users.find((u) => u.name === "Default User") ?? null;
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

    // Create default user if it doesn't exist with metric as default
    const userId = await ctx.db.insert("users", {
      name: "Default User",
      createdAt: Date.now(),
      unit: "metric",
    });

    return userId;
  },
});

// Update user unit preference
export const updateUnit = mutation({
  args: {
    userId: v.id("users"),
    unit: v.union(v.literal("metric"), v.literal("imperial")),
  },
  handler: async (ctx, args) => {
    await ctx.db.patch(args.userId, {
      unit: args.unit,
    });
  },
});
