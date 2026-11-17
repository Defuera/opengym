import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
import { dashboardDays, goalKind, goalStatus, importCounts, importStatus, itemSource, moduleSpec, planExercise, prediction, proposalSource } from "./lib/validators";

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

/** A fact: a user goal. Client-made `goalId` makes writes idempotent. */
export const goalFields = {
  goalId: v.string(),
  title: v.string(),
  kind: goalKind,
  exercise: v.optional(v.string()),
  targetKg: v.optional(v.number()),
  sessionsPerWeek: v.optional(v.number()),
  status: goalStatus,
  source: itemSource,
  threadId: v.optional(v.string()),
  importId: v.optional(v.string()),
  createdAt: v.number(),
};

/** A fact: a context note the coach reads as a training preference. */
export const contextFields = {
  itemId: v.string(),
  text: v.string(),
  topic: v.string(),
  active: v.boolean(),
  source: itemSource,
  threadId: v.optional(v.string()),
  importId: v.optional(v.string()),
  createdAt: v.number(),
};

export default defineSchema({
  // Facts. Written only by commands (ADR-002).
  sessions: defineTable(sessionFields)
    .index("by_sessionId", ["sessionId"])
    .index("by_endedAt", ["endedAt"])
    .index("by_importId", ["importId"]),
  goals: defineTable(goalFields)
    .index("by_goalId", ["goalId"])
    .index("by_createdAt", ["createdAt"])
    .index("by_importId", ["importId"]),
  context: defineTable(contextFields)
    .index("by_itemId", ["itemId"])
    .index("by_createdAt", ["createdAt"])
    .index("by_importId", ["importId"]),
  imports: defineTable({
    importId: v.string(),
    status: importStatus,
    total: v.number(),
    processed: v.number(),
    counts: importCounts,
    notes: v.array(v.string()),
    createdAt: v.number(),
  })
    .index("by_importId", ["importId"])
    .index("by_createdAt", ["createdAt"]),

  // Read models. Written only by jobs. `version` is the dirtyAt of the rebuild that made the row;
  // a job result older than the stored row is dropped.
  plans: defineTable({
    type: v.string(),
    version: v.number(),
    createdAt: v.number(),
    source: proposalSource,
    rationale: v.string(),
    exercises: v.array(planExercise),
  }).index("by_type", ["type"]),
  predictions: defineTable({
    version: v.number(),
    createdAt: v.number(),
    source: proposalSource,
    items: v.array(prediction),
  }),
  dashboards: defineTable({
    days: dashboardDays,
    version: v.number(),
    createdAt: v.number(),
    source: proposalSource,
    modules: v.array(moduleSpec),
  }).index("by_days", ["days"]),
  reviews: defineTable({
    sessionId: v.string(),
    version: v.number(),
    createdAt: v.number(),
    source: proposalSource,
    summary: v.string(),
    changes: v.array(v.string()),
  }).index("by_sessionId", ["sessionId"]),

  // Debounce state for read-model rebuilds (one row). See lib/facts-changed.ts.
  rebuilds: defineTable({
    /** Last time a fact changed. */
    dirtyAt: v.number(),
    /** First change since the last rebuild started; caps how long a steady stream of writes can delay it. */
    dirtySince: v.number(),
    /** True while a runner is scheduled. */
    runnerScheduled: v.boolean(),
    /** How many rebuilds have started. */
    runs: v.number(),
    lastRunAt: v.optional(v.number()),
  }),
});
