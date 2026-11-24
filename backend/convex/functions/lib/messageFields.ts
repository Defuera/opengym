import { v } from "convex/values";

/** The screens a chat message can be sent from (ADR-032). */
export const CONTEXT_SCREENS = ["chat", "log", "session", "exercise", "program", "start"] as const;
/** Screens whose messages run the coach turn with functions in this step (ADR-032 step A). Every other send keeps the old reply. */
export const COACH_TURN_SCREENS = new Set<string>(["session", "exercise"]);

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
});

/** What one function of a coach turn did. Stored on the assistant message, in the order the coach gave. */
export const actionResult = v.object({
  actionId: v.string(),
  name: v.string(),
  status: v.union(v.literal("applied"), v.literal("drafted"), v.literal("rejected")),
  reason: v.optional(v.string()),
});

/** A question of the coach, with optional quick answers. A quick answer is sent back as an ordinary message. */
export const coachQuestion = v.object({
  text: v.string(),
  answers: v.optional(v.array(v.object({ id: v.string(), label: v.string() }))),
});
