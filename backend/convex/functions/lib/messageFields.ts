import { v } from "convex/values";
import { planExercise } from "./validators";

/** The screens a chat message can be sent from (ADR-032). */
export const CONTEXT_SCREENS = ["chat", "log", "session", "exercise", "goal", "limit", "note", "program", "start"] as const;
/**
 * Screens whose messages run the coach turn with functions (ADR-032): the general chat, the log chat, the session, an exercise, and the goal, limit and note chats (step D).
 * A send with no screen, from "program" or from "start" keeps the old reply until those screens move (ADR-032, proposed next steps).
 */
export const COACH_TURN_SCREENS = new Set<string>(["chat", "log", "session", "exercise", "goal", "limit", "note"]);

/**
 * What was open when the person sent a message (ADR-032). A hint from the app, never permission: the server reads the real
 * open session, exercise and places itself. Stored on the user message.
 */
export const messageContext = v.object({
  screen: v.optional(v.union(...CONTEXT_SCREENS.map((s) => v.literal(s)))),
  openSessionId: v.optional(v.string()),
  exerciseId: v.optional(v.string()),
  placeId: v.optional(v.string()),
  entryId: v.optional(v.string()),
  programId: v.optional(v.string()),
  /** The goal, limit or note the person wants to change (ADR-032, step D). */
  goalId: v.optional(v.string()),
  limitId: v.optional(v.string()),
  noteId: v.optional(v.string()),
  /** The body part key of a new limit ("left_knee"), from a tap on the body figure. */
  part: v.optional(v.string()),
});

/** What one function of a coach turn did. Stored on the assistant message, in the order the coach gave. */
export const actionResult = v.object({
  actionId: v.string(),
  name: v.string(),
  status: v.union(v.literal("applied"), v.literal("drafted"), v.literal("rejected")),
  reason: v.optional(v.string()),
  /** A plain line of what the function did, made by code from the checked arguments and the data (max 120). */
  detail: v.optional(v.string()),
});

/** The whole-session plan the coach proposes (ADR-032). `exercises` are checked against the plan safety limits. `appliedAt` is set when the person approved it. */
export const coachProposal = v.object({
  /** Absent on proposals stored before the log draft existed: they are "session". */
  type: v.optional(v.literal("session")),
  title: v.optional(v.string()),
  exercises: v.array(planExercise),
  focus: v.optional(v.string()),
  planNote: v.optional(v.string()),
  /** The rev of the open session the coach read. */
  rev: v.number(),
  /** The open session the proposal is for. */
  openSessionId: v.string(),
  appliedAt: v.optional(v.number()),
});

/**
 * A log draft the coach makes in the log chat (ADR-032): what the person is logging, held on the assistant message until the person presses Done.
 * `session`, `goal`, `limit` and `note` are the parts, already checked (zod and plain code) when the draft was made. `plain` is a draft made by code
 * (no AI answer): a plain note of kind "other". `entryId` is set when Done wrote it.
 */
export const logProposal = v.object({
  type: v.literal("log"),
  kind: v.string(),
  /** The colour of the category (#RRGGBB), copied from the stored category when the draft was made. */
  color: v.optional(v.string()),
  summary: v.string(),
  at: v.number(),
  session: v.optional(v.any()),
  goal: v.optional(v.any()),
  limit: v.optional(v.any()),
  note: v.optional(v.any()),
  edits: v.optional(v.object({ goalId: v.optional(v.string()), limitId: v.optional(v.string()), noteId: v.optional(v.string()) })),
  /** Made outside the log chat: Done writes the parts only, no entry. */
  noEntry: v.optional(v.boolean()),
  plain: v.optional(v.boolean()),
  appliedAt: v.optional(v.number()),
  entryId: v.optional(v.string()),
});

/** What an assistant message may hold as its proposal. */
export const storedProposal = v.union(coachProposal, logProposal);

/** A question of the coach, with optional quick answers. A quick answer is sent back as an ordinary message. */
export const coachQuestion = v.object({
  text: v.string(),
  answers: v.optional(v.array(v.object({ id: v.string(), label: v.string() }))),
});
