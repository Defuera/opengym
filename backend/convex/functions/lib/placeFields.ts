import { v } from "convex/values";
import { activityKey } from "../model/sessionShape";

/** Longest place name and equipment text; the longest quote kept in a trace row (ADR-021). */
export const PLACE_NAME_MAX = 30;
export const PLACE_TEXT_MAX = 1500;
export const PLACE_QUOTE_MAX = 300;

/** The matching key of a place name: trim, lower case, inner whitespace collapsed (the same rule as an activity name). */
export const placeKey = activityKey;

/** Who changed the text of a place. "user": the place command. The rest are the background job (and the one-off seed). */
export const placeChangeSource = v.union(v.literal("feedback"), v.literal("note"), v.literal("chat"), v.literal("user"), v.literal("seed"));

/**
 * How much the text of a place says (ADR-032). "partial": learned from the person's log and messages, never a full list.
 * "unknown": nothing is known yet. Absent = "partial" (model/placeKnowledge.ts reads it).
 */
export const placeKnowledgeState = v.union(v.literal("partial"), v.literal("unknown"));

/** What a change of a place text rests on (ADR-032): the person's own words, or a photo the person attached. */
export const placeEvidence = v.union(v.literal("person_said"), v.literal("seen_in_photo"));

/** A fact (ADR-021): where the user trains and what is there, in free text. `placeId` is client- or server-made. */
export const placeFields = {
  placeId: v.string(),
  name: v.string(),
  /** Free text: the equipment. May be empty (= not known yet). Never a full list (ADR-032). */
  text: v.string(),
  knowledgeState: v.optional(placeKnowledgeState),
  createdAt: v.number(),
  updatedAt: v.number(),
};

/** The trace of one change of a place text. Never read by the app. */
export const placeChangeFields = {
  placeId: v.string(),
  at: v.number(),
  source: placeChangeSource,
  quote: v.string(),
  before: v.string(),
  after: v.string(),
  /** Set by the coach turn (ADR-032). Absent on the rows of the other writers. */
  evidence: v.optional(placeEvidence),
};
