import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

/** One logged set. `reps` = completed reps; `failed` = one more rep was tried and not completed. */
export const setEntry = v.object({
  reps: v.number(),
  kg: v.number(),
  max: v.boolean(),
  failed: v.optional(v.boolean()),
  at: v.optional(v.number()),
});

export const exercise = v.object({ name: v.string(), sets: v.array(setEntry) });

/** A fact: written only by the app or by an import the user started. Never by the AI. */
export const sessionFields = {
  /** Client-made id, so an offline write can be retried safely. */
  sessionId: v.string(),
  kind: v.union(v.literal("gym"), v.literal("activity")),
  type: v.string(),
  startedAt: v.number(),
  endedAt: v.number(),
  exercises: v.array(exercise),
  minutes: v.optional(v.number()),
  distanceKm: v.optional(v.number()),
  note: v.optional(v.string()),
  source: v.union(v.literal("app"), v.literal("import")),
  importId: v.optional(v.string()),
};

export default defineSchema({
  sessions: defineTable(sessionFields)
    .index("by_sessionId", ["sessionId"])
    .index("by_endedAt", ["endedAt"])
    .index("by_importId", ["importId"]),
});
