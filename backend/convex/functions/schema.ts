import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
import { actionResult, coachQuestion, messageContext, storedProposal } from "./lib/messageFields";
import { placeChangeFields, placeFields } from "./lib/placeFields";
import { programFields, proposalFields, threadAbout } from "./lib/programFields";
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
 * `comment` is what the person wrote about this exercise in this session (ADR-029): how it went that day. A fact, the person's words.
 */
export const exercise = v.union(
  v.object({ name: v.string(), measure: v.optional(v.literal("sets")), sets: v.array(setEntry), comment: v.optional(v.string()) }),
  v.object({ name: v.string(), measure: v.literal("time"), sets: v.array(timeEntry), comment: v.optional(v.string()) }),
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
  /** Where the session happened (ADR-021). Set by the app, by commands/sessions:setPlace or by jobs/places:seed. Absent = not known. */
  placeId: v.optional(v.string()),
  /** The program this session belongs to, and where in it (written by the app, from `queries/programs:list` `next`). Absent on every other session. */
  programId: v.optional(v.string()),
  programWeek: v.optional(v.number()),
  programSlot: v.optional(v.number()),
  programKey: v.optional(v.string()),
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

/**
 * What the reader job found in an entry (ADR-031). Not a fact: an AI label on the fact. `rev` names the text and files that
 * were read; a label for an older text is never shown as current. `kind` and `summary` are set only when `status` is "ready".
 */
export const entryRead = v.object({
  status: v.union(v.literal("pending"), v.literal("ready"), v.literal("failed")),
  rev: v.string(),
  /** A short category label ("Meal", "Sleep", ...; at most 24 characters). Old rows hold "meal", "training", "body", "goal" or "other". */
  kind: v.optional(v.string()),
  summary: v.optional(v.string()),
  /** The rows the log chat wrote with this entry when the person pressed Done (ADR-032). */
  made: v.optional(v.object({ sessionId: v.optional(v.string()), goalId: v.optional(v.string()), limitId: v.optional(v.string()), contextId: v.optional(v.string()) })),
});

const openSet = v.object({
  reps: v.optional(v.number()),
  kg: v.optional(v.number()),
  max: v.optional(v.boolean()),
  failed: v.optional(v.boolean()),
  minutes: v.optional(v.number()),
  distanceKm: v.optional(v.number()),
  done: v.boolean(),
  at: v.optional(v.number()),
});

/** The open session in the app's own shape (ADR-028). Not a fact until the app finishes it and saves a session. */
export const openSessionFields = {
  id: v.string(),
  kind: v.literal("gym"),
  type: v.string(),
  focus: v.optional(v.string()),
  startedAt: v.number(),
  source: v.optional(v.string()),
  planNote: v.optional(v.string()),
  placeId: v.optional(v.string()),
  programId: v.optional(v.string()),
  programWeek: v.optional(v.number()),
  programSlot: v.optional(v.number()),
  programKey: v.optional(v.string()),
  exercises: v.array(
    v.object({
      id: v.string(),
      name: v.string(),
      measure: v.optional(v.literal("time")),
      sets: v.array(openSet),
      fresh: v.optional(v.boolean()),
      carry: v.optional(v.boolean()),
      /** The plan note the coach wrote for the exercise. */
      note: v.optional(v.string()),
      /** What the person wrote about the exercise (ADR-029). Only the app writes it. */
      comment: v.optional(v.string()),
    }),
  ),
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
  entries: defineTable({ ...entryFields, read: v.optional(entryRead) }).index("by_entryId", ["entryId"]).index("by_at", ["at"]).index("by_deletedAt", ["deletedAt"]),
  // Exercise art: one image per exercise name (two key poses side by side). The key is artKey(name).
  // The categories of log entries (ADR-031): one row per category, unique by `key` (the lower-cased label). The colour is chosen once,
  // by the AI or by plain code, and never changes by itself. `source` says which.
  entryCategories: defineTable({ key: v.string(), label: v.string(), color: v.string(), createdAt: v.number(), source: v.union(v.literal("ai"), v.literal("rules")) }).index("by_key", ["key"]),
  exerciseArt: defineTable({
    key: v.string(),
    name: v.string(),
    status: v.union(v.literal("pending"), v.literal("ready"), v.literal("failed")),
    storageId: v.optional(v.id("_storage")),
    sourceId: v.optional(v.string()),
    model: v.optional(v.string()),
    // The result of the check that the figure stays in place (model/poseShift.ts), and how many pictures were drawn.
    shift: v.optional(v.object({ dx: v.number(), dy: v.number() })),
    tries: v.optional(v.number()),
    error: v.optional(v.string()),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_key", ["key"])
    .index("by_updatedAt", ["updatedAt"]),
  places: defineTable(placeFields).index("by_placeId", ["placeId"]),
  // Trace of every change of a place text (ADR-021), so a wrong line can be traced and undone. Never read by the app.
  placeChanges: defineTable(placeChangeFields).index("by_placeId", ["placeId"]),
  // A program the person agreed to (see lib/programFields.ts). Written only by commands/proposals:accept and commands/programs.
  programs: defineTable(programFields).index("by_programId", ["programId"]).index("by_deletedAt", ["deletedAt"]),
  // A coach proposal waiting for the person (a new or changed program). Not a fact. Written by commands/proposals and jobs/programs. Removed after 7 days.
  proposals: defineTable(proposalFields).index("by_proposalId", ["proposalId"]).index("by_createdAt", ["createdAt"]).index("by_threadId", ["threadId"]),
  limits: defineTable({ ...limitFields, importId: v.optional(v.string()) }).index("by_limitId", ["limitId"]),
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
    /** The place this conversation is about (ADR-021). The coach reads it and learns from the user's messages here. */
    placeId: v.optional(v.string()),
    /** What this conversation is about (ADR-026). Set when the thread is created, from the thing it is opened from. The app hides such threads from the chat list by default. */
    about: v.optional(threadAbout),
    /** The open session this chat was opened from: `context.openSessionId` of its first user message. The app finds the thread of an open session again by it. */
    openSessionId: v.optional(v.string()),
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
    /** Set only on a voice message (jobs/voice): the transcript is pending, done or failed. The text is empty until done. */
    voice: v.optional(v.union(v.literal("pending"), v.literal("done"), v.literal("failed"))),
    /** Only on an assistant message: the proposal the coach made with this message (ADR-026). The proposal may be gone after 7 days. */
    proposalId: v.optional(v.string()),
    /** Only on a user message: what was open when it was sent (ADR-032). */
    context: v.optional(messageContext),
    /** Only on an assistant message of a coach turn (ADR-032): the user message it answers. One answer per turn. */
    turnId: v.optional(v.string()),
    /** Only on an assistant message of a coach turn: what each function did, in order. */
    actions: v.optional(v.array(actionResult)),
    /** Only on an assistant message of a coach turn: the coach asks the person, with optional quick answers. */
    question: v.optional(coachQuestion),
    /** Only on an assistant message of a coach turn: the whole-session plan the coach proposes; applied when the person approves (ADR-032). */
    proposal: v.optional(storedProposal),
    /** Only on an assistant message that answers "Done" of a log draft: the entry it wrote. */
    entryId: v.optional(v.string()),
    /** Only on a user message that is a tap on a quick answer (ADR-032): the answered turn and the answer. */
    answer: v.optional(v.object({ turnId: v.string(), id: v.string() })),
    createdAt: v.number(),
  })
    .index("by_messageId", ["messageId"])
    .index("by_threadId", ["threadId"])
    .index("by_turnId", ["turnId"]),
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
    // On a rebuild: the place of the proposal the person saw (ADR-035). A rebuild keeps it unless the feedback names another place.
    previousPlaceId: v.optional(v.string()),
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

  // One row per AI job run (ADR-027): the exact prompt sent, every attempt, the outcome. For reading the coach's real answers; no code reads it
  // for the app. Written by jobs/aiCalls:save. Erased after 90 days by jobs/purge:run. Images are counted, not kept.
  aiCalls: defineTable({
    at: v.number(),
    job: v.string(),
    provider: v.string(),
    model: v.optional(v.string()),
    system: v.string(),
    messages: v.array(v.object({ role: v.union(v.literal("user"), v.literal("assistant")), content: v.string() })),
    images: v.number(),
    attempts: v.array(v.object({ raw: v.optional(v.string()), error: v.optional(v.string()), ms: v.number() })),
    path: v.union(v.literal("ai"), v.literal("fallback")),
    reason: v.optional(v.string()),
    ms: v.number(),
    /** What the call was for: the turn id (the user message id) of a coach turn. Optional: rows of other jobs and older rows have none. */
    ref: v.optional(v.string()),
    /** The result of each action of a coach turn (applied, drafted or rejected with the reason), written by jobs/coachTurn:save, so a bad turn can be diagnosed. */
    actions: v.optional(v.array(actionResult)),
  })
    .index("by_at", ["at"])
    .index("by_job", ["job", "at"]),

  // The open session (ADR-028): at most one row, the session the person is doing now, in the app's own shape. The app writes it on every
  // change (commands/openSession:put) and removes it when the session ends. An outside writer changes only the part that is not done
  // (jobs/openSession:replacePlan). `rev` grows by one on every write; the app takes an outside change only when `rev` is newer than its own.
  openSession: defineTable({ ...openSessionFields, rev: v.number(), updatedAt: v.number(), updatedBy: v.union(v.literal("app"), v.literal("coach"), v.literal("owner")) }),

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
