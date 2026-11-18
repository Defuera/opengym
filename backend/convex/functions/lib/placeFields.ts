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

/** A fact (ADR-021): where the user trains and what is there, in free text. `placeId` is client- or server-made. */
export const placeFields = {
  placeId: v.string(),
  name: v.string(),
  /** Free text: the equipment. May be empty (= not known yet). */
  text: v.string(),
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
};
