import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

// Schema for OpenGym data model
// This defines the structure for users, sessions, exercises, and sets
export default defineSchema({
  users: defineTable({
    name: v.string(),
    createdAt: v.number(),
  }),

  sessions: defineTable({
    userId: v.id("users"),
    date: v.number(),
    status: v.union(
      v.literal("planned"),
      v.literal("active"),
      v.literal("completed")
    ),
    createdAt: v.number(),
    updatedAt: v.number(),
  }).index("by_user", ["userId"]),

  exercises: defineTable({
    sessionId: v.id("sessions"),
    name: v.string(),
    muscleGroup: v.string(),
    order: v.number(),
  }).index("by_session", ["sessionId"]),

  sets: defineTable({
    exerciseId: v.id("exercises"),
    reps: v.number(),
    weight: v.number(),
    order: v.number(),
  }).index("by_exercise", ["exerciseId"]),
});
