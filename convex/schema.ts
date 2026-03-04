import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

// Schema for OpenGym data model
// This defines the structure for users, sessions, exercises, and sets
export default defineSchema({
  users: defineTable({
    name: v.string(),
    createdAt: v.number(),
    unit: v.optional(v.union(v.literal("metric"), v.literal("imperial"))),
  }),

  sessions: defineTable({
    userId: v.id("users"),
    name: v.optional(v.string()),
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
    // userId is stored here for efficient by-user queries (avoids N+1 through sessions).
    // Optional for backward compatibility with records created before this field was added.
    userId: v.optional(v.id("users")),
    name: v.string(),
    muscleGroup: v.string(),
    order: v.number(),
  })
    .index("by_session", ["sessionId"])
    .index("by_user", ["userId"]),

  sets: defineTable({
    exerciseId: v.id("exercises"),
    reps: v.number(),
    weight: v.number(),
    order: v.number(),
    status: v.optional(
      v.union(
        v.literal("todo"),
        v.literal("later"),
        v.literal("complete")
      )
    ),
  }).index("by_exercise", ["exerciseId"]),

  aiMemories: defineTable({
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
    createdAt: v.number(),
    updatedAt: v.number(),
    archivedAt: v.optional(v.number()),
  }).index("by_user", ["userId"]),

  aiThreads: defineTable({
    userId: v.id("users"),
    title: v.optional(v.string()),
    createdAt: v.number(),
    updatedAt: v.number(),
    archivedAt: v.optional(v.number()),
  }).index("by_user", ["userId"]),

  aiMessages: defineTable({
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
    createdAt: v.number(),
    deletedAt: v.optional(v.number()),
  }).index("by_thread", ["threadId"]),

  aiActions: defineTable({
    messageId: v.id("aiMessages"),
    threadId: v.id("aiThreads"),
    toolCallId: v.string(),
    toolName: v.string(),
    toolArgs: v.string(),
    description: v.string(),
    status: v.union(
      v.literal("pending"),
      v.literal("confirmed"),
      v.literal("rejected")
    ),
    result: v.optional(v.string()),
    createdAt: v.number(),
    resolvedAt: v.optional(v.number()),
  })
    .index("by_thread", ["threadId"])
    .index("by_message", ["messageId"]),

  sessionSummaries: defineTable({
    userId: v.string(),
    sessionId: v.id("sessions"),
    trend: v.union(
      v.literal("improving"),
      v.literal("stable"),
      v.literal("declining"),
      v.literal("insufficient_data")
    ),
    score: v.number(),
    headline: v.string(),
    highlights: v.array(v.string()),
    muscleGroups: v.array(v.string()),
    generatedAt: v.number(),
    reviewText: v.optional(v.string()),
    exerciseReviews: v.optional(
      v.array(
        v.object({
          name: v.string(),
          assessment: v.string(),
          trend: v.string(),
          topSet: v.string(),
        })
      )
    ),
    coachNotes: v.optional(v.array(v.string())),
    nextSessionFocus: v.optional(v.string()),
  }).index("by_user", ["userId"]).index("by_session", ["sessionId"]),
});
