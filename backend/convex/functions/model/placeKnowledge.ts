/**
 * What the coach knows about a place, and how a prompt says it (ADR-032). The text of a place is learned from the person's
 * log and messages (ADR-021). It is never a full list: equipment that the text does not name is unknown, not missing.
 */
export type PlaceKnowledge = "partial" | "unknown";

/** The knowledge state of a place. Absent = "partial"; an empty text is always "unknown". */
export function knowledgeOf(p: { text: string; knowledgeState?: PlaceKnowledge }): PlaceKnowledge {
  if (!p.text.trim()) return "unknown";
  return p.knowledgeState ?? "partial";
}

/** One sentence for every prompt that holds places: what a place text is, and what it is not. */
export const PLACE_KNOWLEDGE_RULE =
  'What a place lists was learned from the person\'s log and messages (knowledge "partial"), or nothing is known yet (knowledge "unknown"). It is never a full list of what is there. Equipment that a place does not name is unknown, not missing: never write that something is missing or not at a place unless the person said so.';

/** One sentence for every prompt that plans or changes a session at a place. */
export const SESSION_PLACE_RULE =
  "Never choose or imply a different place than the session's place because a place does not name an item.";
