import { v } from "convex/values";

export const itemSource = v.union(v.literal("user"), v.literal("ai"), v.literal("import"));
export const proposalSource = v.union(v.literal("ai"), v.literal("rules"));
export const goalKind = v.union(v.literal("strength"), v.literal("consistency"), v.literal("custom"));
export const goalStatus = v.union(v.literal("active"), v.literal("done"));
/** Where the AI reading of a text-logged session stands (ADR-018). Absent on every other session. */
export const parseState = v.union(v.literal("pending"), v.literal("done"), v.literal("failed"));
export const dashboardDays = v.union(v.literal(7), v.literal(30));

export const planSet = v.object({ reps: v.number(), kg: v.number(), max: v.boolean() });
export const planTimeSet = v.object({ minutes: v.number(), distanceKm: v.optional(v.number()) });
export const planExercise = v.union(
  v.object({ name: v.string(), measure: v.optional(v.literal("sets")), sets: v.array(planSet), note: v.optional(v.string()) }),
  v.object({ name: v.string(), measure: v.literal("time"), sets: v.array(planTimeSet), note: v.optional(v.string()) }),
);
export const prediction = v.object({ kind: v.union(v.literal("gym"), v.literal("activity")), type: v.string(), focus: v.optional(v.string()), reason: v.string() });

/** The compact copy of a plan kept on a feedback request: exercise names with their sets, no notes. */
export const previousPlan = v.array(v.union(
  v.object({ name: v.string(), measure: v.optional(v.literal("sets")), sets: v.array(planSet) }),
  v.object({ name: v.string(), measure: v.literal("time"), sets: v.array(planTimeSet) }),
));

export const startStatus = v.union(v.literal("pending"), v.literal("ready"), v.literal("failed"));
/** The place of a start proposal (ADR-021): what the app needs to show it. */
export const proposalPlace = v.object({ placeId: v.string(), name: v.string() });

/** The stored proposal of a start request. The plan is the safe-checked draft; the app gets it in the plan shape of queries/plans:next. */
export const startProposal = v.object({
  kind: v.union(v.literal("gym"), v.literal("activity")),
  type: v.string(),
  focus: v.optional(v.string()),
  minutes: v.optional(v.number()),
  reason: v.optional(v.string()),
  plan: v.optional(v.object({ source: proposalSource, rationale: v.string(), exercises: v.array(planExercise) })),
  /** Where the session is for (ADR-021). Set in code by jobs/startRequest:save. */
  place: v.optional(proposalPlace),
  /** The program session this is (ADR-030). Set in code by jobs/startRequest:save; the app writes it on the session. */
  program: v.optional(v.object({ programId: v.string(), week: v.number(), slot: v.number(), key: v.string() })),
});

/** What the interpret_request job hands to the save step: the same, with the plan as a bare draft (the source is a separate argument). */
export const startDraft = v.object({
  kind: v.union(v.literal("gym"), v.literal("activity")),
  type: v.string(),
  focus: v.optional(v.string()),
  minutes: v.optional(v.number()),
  reason: v.optional(v.string()),
  plan: v.optional(v.object({ rationale: v.string(), exercises: v.array(planExercise) })),
  /** The place NAME the coach chose (a known one or a new one). jobs/startRequest:save maps it to a place. */
  place: v.optional(v.string()),
  /** The program session the coach says this is. jobs/startRequest:save finds the week and the slot. */
  program: v.optional(v.object({ programId: v.string(), key: v.string() })),
});

/** Dashboard layout spec: which modules, in what order. Numbers are never stored (computed by code). */
export const moduleSpec = v.union(
  v.object({ type: v.literal("stat"), which: v.union(v.literal("sessions"), v.literal("active_days"), v.literal("sets"), v.literal("top_set")) }),
  v.object({ type: v.literal("goal_progress"), goalId: v.string() }),
  v.object({ type: v.literal("trend"), exercise: v.optional(v.string()) }),
  v.object({ type: v.literal("consistency") }),
  v.object({ type: v.literal("recent_sessions"), limit: v.optional(v.number()) }),
  v.object({ type: v.literal("note"), text: v.string() }),
);

export const importCounts = v.object({ sessions: v.number(), goals: v.number(), context: v.number() });
export const importStatus = v.union(v.literal("running"), v.literal("done"), v.literal("failed"));

export const threadStatus = v.union(v.literal("idle"), v.literal("thinking"), v.literal("failed"));
export const fileKind = v.union(v.literal("text"), v.literal("image"), v.literal("pdf"), v.literal("audio"), v.literal("other"));

/** What extract_from_chat may propose (the model's GoalInput / ContextInput). */
export const goalInput = v.object({
  title: v.string(),
  kind: goalKind,
  exercise: v.optional(v.string()),
  targetKg: v.optional(v.number()),
  sessionsPerWeek: v.optional(v.number()),
});
export const contextInput = v.object({ text: v.string(), topic: v.string() });

export const limitStatus = v.union(v.literal("active"), v.literal("improving"), v.literal("cleared"));
export const ruleKind = v.union(v.literal("avoid"), v.literal("light"), v.literal("do"));
export const feeling = v.union(v.literal("fine"), v.literal("noticed"), v.literal("bad"));
export const limitRule = v.object({ kind: ruleKind, text: v.string(), exercises: v.optional(v.array(v.string())) });
