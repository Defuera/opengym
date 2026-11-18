import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
import { previousPlan, startProposal, startStatus, dashboardDays, feeling, limitRule, limitStatus, fileKind, threadStatus, goalKind, goalStatus, importCounts, importStatus, itemSource, moduleSpec, parseState, planExercise, prediction, proposalSource } from "./lib/validators";

/** One logged set. `reps` = completed reps; `failed` = one more rep was tried and not completed. */
export const setEntry = v.object({
  reps: v.number(),
  kg: v.number(),
  max: v.boolean(),
  failed: v.optional(v.boolean()),
  at: v.optional(v.number()),
});

/** One entry of a time exercise: minutes and optionally the distance. */
export const timeEntry = v.object({
  minutes: v.number(),
  distanceKm: v.optional(v.number()),
  note: v.optional(v.string()),
  at: v.optional(v.number()),
});

/**
 * An exercise: `measure` is absent in all old rows (= "sets"). A "time" exercise holds timeEntry items, any other holds
 * setEntry items. Two shapes, told apart by `measure`.
 */
export const exercise = v.union(
  v.object({ name: v.string(), measure: v.optional(v.literal("sets")), sets: v.array(setEntry) }),
  v.object({ name: v.string(), measure: v.literal("time"), sets: v.array(timeEntry) }),
);

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
  /** Set by commands/sessions:logText: "pending" until the parse_log job has read the note, then "done" or "failed" (ADR-018). */
  parse: v.optional(parseState),
  /** Set by commands/sessions:remove (ADR-020). A marked row is invisible to every read; jobs/purge erases it after DELETE_AFTER_MS. */
  deletedAt: v.optional(v.number()),
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

/** A fact: a free note with a time and attached files (ADR-017). Client-made `entryId`. `at` is the time the entry is about. */
export const entryFields = {
  entryId: v.string(),
  text: v.string(),
  fileIds: v.array(v.string()),
  at: v.number(),
  createdAt: v.number(),
  /** Set by commands/entries:remove (ADR-020). Same rule as `sessions.deletedAt`. */
  deletedAt: v.optional(v.number()),
};

export default defineSchema({
  // Facts. Written only by commands (ADR-002).
  sessions: defineTable(sessionFields)
    .index("by_sessionId", ["sessionId"])
    .index("by_endedAt", ["endedAt"])
    .index("by_importId", ["importId"])
    .index("by_deletedAt", ["deletedAt"]),
  goals: defineTable(goalFields)
    .index("by_goalId", ["goalId"])
    .index("by_createdAt", ["createdAt"])
    .index("by_importId", ["importId"]),
  context: defineTable(contextFields)
    .index("by_itemId", ["itemId"])
    .index("by_createdAt", ["createdAt"])
    .index("by_importId", ["importId"]),
  entries: defineTable(entryFields).index("by_entryId", ["entryId"]).index("by_at", ["at"]).index("by_deletedAt", ["deletedAt"]),
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
    /** How the title was set. "auto": by code or by the title job; the user has not named it. "user": the user named or renamed it; never overwritten. A row without it counts as "user". */
    titleSource: v.optional(v.union(v.literal("auto"), v.literal("user"))),
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
    // The wish (what the user wants). Optional: a request may carry only a name.
    text: v.optional(v.string()),
    // The fixed session name (1..40). When set, the proposal type is always this name.
    name: v.optional(v.string()),
    // Feedback on a proposed session (1..300 each, at most 5, oldest first) and the plan it was given on. Set only by a rebuild request.
    feedback: v.optional(v.array(v.string())),
    previousPlan: v.optional(previousPlan),
    // Legacy fields of the removed "today" mode. Old rows may hold them, so they stay optional and are never written or read now.
    mode: v.optional(v.literal("today")),
    hintType: v.optional(v.string()),
    hintFocus: v.optional(v.string()),
    status: startStatus,
    createdAt: v.number(),
    proposal: v.optional(startProposal),
  })
    .index("by_requestId", ["requestId"])
    .index("by_createdAt", ["createdAt"]),

  // Owner settings (one row). `aiModel` is the coach model chosen in the app; absent = the model from the environment.
  // `modelList` is the provider's model list, cached by jobs/models:refresh. `modelListError` is a short text without secrets.
  settings: defineTable({
    aiModel: v.optional(v.string()),
    modelList: v.optional(v.object({ models: v.array(v.string()), fetchedAt: v.number() })),
    modelListError: v.optional(v.string()),
  }),

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
