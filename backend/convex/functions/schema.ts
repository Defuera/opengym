import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
import { startProposal, startStatus, dashboardDays, feeling, limitRule, limitStatus, fileKind, threadStatus, goalKind, goalStatus, importCounts, importStatus, itemSource, moduleSpec, planExercise, prediction, proposalSource } from "./lib/validators";

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
  /** The activity: "Gym" for kind gym. Old rows may still hold the flavour here (see jobs/migrations:activityFirst). */
  type: v.string(),
  /** The flavour of the session ("Upper", "Legs", "Easy"). Optional. */
  focus: v.optional(v.string()),
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

/** A fact: a body part the user trains around. Client-made `limitId`. */
export const limitFields = {
  limitId: v.string(),
  part: v.string(),
  title: v.string(),
  status: limitStatus,
  since: v.optional(v.string()),
  rules: v.array(limitRule),
};

/** A fact: the user's own record text for a limit. Never read by an AI job (ADR-015). */
export const recordFields = {
  recordId: v.string(),
  limitId: v.string(),
  title: v.string(),
  date: v.optional(v.string()),
  text: v.string(),
};

/** A fact: how a limited body part felt, as the user said it. */
export const checkinFields = {
  checkinId: v.string(),
  limitId: v.string(),
  sessionId: v.optional(v.string()),
  at: v.number(),
  feeling,
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
  limits: defineTable(limitFields).index("by_limitId", ["limitId"]),
  records: defineTable(recordFields).index("by_recordId", ["recordId"]).index("by_limitId", ["limitId"]),
  checkins: defineTable(checkinFields)
    .index("by_checkinId", ["checkinId"])
    .index("by_limitId", ["limitId"])
    .index("by_sessionId", ["sessionId"]),
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

  // Chat. Written by commands (user messages) and by the chat job (assistant messages, status).
  threads: defineTable({
    threadId: v.string(),
    title: v.string(),
    createdAt: v.number(),
    updatedAt: v.number(),
    summary: v.string(),
    lastMessage: v.optional(v.string()),
    /** thinking: a coach reply is running. failed: the last reply failed (see `error`). */
    status: threadStatus,
    error: v.optional(v.string()),
    /** Coach replies still running (one per unanswered message). Status is `thinking` while > 0. */
    pending: v.number(),
  })
    .index("by_threadId", ["threadId"])
    .index("by_updatedAt", ["updatedAt"]),
  messages: defineTable({
    messageId: v.string(),
    threadId: v.string(),
    role: v.union(v.literal("user"), v.literal("assistant")),
    text: v.string(),
    fileIds: v.array(v.string()),
    sources: v.array(v.string()),
    createdAt: v.number(),
  })
    .index("by_messageId", ["messageId"])
    .index("by_threadId", ["threadId"]),
  files: defineTable({
    fileId: v.string(),
    storageId: v.id("_storage"),
    name: v.string(),
    mime: v.string(),
    size: v.number(),
    kind: fileKind,
    createdAt: v.number(),
  }).index("by_fileId", ["fileId"]),

  // Read models. Written only by jobs. `version` is the dirtyAt of the rebuild that made the row;
  // a job result older than the stored row is dropped.
  plans: defineTable({
    /** The activity the plan is for, as the log spells it ("Gym", "Home"). Absent on a row from before ADR-016: that is a Gym plan. */
    activity: v.optional(v.string()),
    /** activityKey(activity). The plan key is (activityKey, focusKey). Absent on a pre-ADR-016 row; the first rebuild replaces it. */
    activityKey: v.optional(v.string()),
    /** activityKey(focus), "" when the plan has no focus. */
    focusKey: v.optional(v.string()),
    /** The focus the plan is for. Absent when the plan has none. Optional on old rows until jobs/migrations:activityFirst has run. */
    focus: v.optional(v.string()),
    /** Legacy key (the old gym type). Never written now; the migration moves it to `focus`. */
    type: v.optional(v.string()),
    version: v.number(),
    createdAt: v.number(),
    source: proposalSource,
    rationale: v.string(),
    exercises: v.array(planExercise),
  })
    .index("by_focus", ["focus"])
    .index("by_activity", ["activityKey", "focusKey"]),
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

  // A typed "Start session" request (ADR-016). Not a fact: it holds what the user typed and the proposal the AI job made.
  // Written by commands/start:request and jobs/startRequest. Removed after one day.
  startRequests: defineTable({
    requestId: v.string(),
    text: v.string(),
    status: startStatus,
    createdAt: v.number(),
    proposal: v.optional(startProposal),
  })
    .index("by_requestId", ["requestId"])
    .index("by_createdAt", ["createdAt"]),

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
