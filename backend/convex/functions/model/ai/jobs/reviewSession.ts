import type { JobDef } from "../runJob";
import { LIMITS_RULE, TRACKER_RULE, dataPrompt, systemPrompt } from "../promptRules";
import { type LimitForAi, type ReviewDraft, ReviewDraftSchema } from "../../schema";
import type { ReviewFacts } from "../../reviewFacts";
import type { coachPicture } from "./coachPicture";
import { limitsForPrompt } from "./shared";

export interface ReviewInput {
  /** The time zone of the user (ADR-039). */
  timeZone?: string;
  /** The facts of the session, all numbers made in code from the history (model/reviewFacts.ts). */
  facts: ReviewFacts;
  /** The limits with their records, cleared ones too (ADR-033). */
  limits: LimitForAi[];
  /** The picture of the person as it was BEFORE this session; the review reads the goals, the notes and the tracker of it. Absent in old callers. */
  picture?: ReturnType<typeof coachPicture>;
}

/** The debrief (ADR-041): an evaluation in the coach's own voice, never a restatement of the log, ending in a question the person can answer. */
const ROLE = `You are the personal coach of the person described in the data. They have just finished the session in "facts". Say what a good coach who has trained this person for a long time would say to them right after it, in a natural human voice: direct, warm, informal.

The person knows what they did and can see their own log, so never read it back. Evaluate it: what was good, what was not, where the person stands against the plan, the program and the goals, and what to look for next session (one thing at most). Weave it into talk; no labelled parts, no list. Name an exercise only to make a judgement about it. Say "wow, that's a big jump" when it is one; push ("short one today and you skipped two exercises, what happened?") only when the facts show a reason: clearly shorter or fewer sets than usual, planned work skipped, the same weights for weeks, or going far beyond the plan where a limit applies. Praise only what the facts support.

facts holds numbers that code made; they are the only numbers you may use. Do not add, subtract or work out any number yourself: use the change, the verdict and the comparison as given.

The message is 2 to 4 short sentences. The question comes after it and is shown with it: ask ONE question about what you cannot see (pain, how a body part that has a limit took the load, how hard it was, how the person feels, or why something was skipped), chosen from the facts (far above the plan on an exercise that loads a body part with a limit: ask about that body part). Give 2 to 4 short answers the person can tap. Leave the question out only when nothing in the facts calls for one.

${LIMITS_RULE} Apply a limit only to the body part and movement it names; a word match is not enough (turning the trunk is not twisting the knee). ${TRACKER_RULE}`;

const SHAPE = `{"message": string (2 to 4 short sentences, max 450 chars), "question"?: {"text": string (max 120), "answers": string[] (2 to 4 labels, each max 24 chars)}}`;

/** What the model sees: the facts, and the goals, limits, notes and tracker readings as they were before the session. */
export function reviewData(i: ReviewInput) {
  return {
    facts: i.facts,
    ...(i.picture ? { goalsInOrderOfPriority: i.picture.goalsInOrderOfPriority, notesFromTheUser: i.picture.notesFromTheUser, ...(i.picture.trackerFromThePhone ? { trackerFromThePhone: i.picture.trackerFromThePhone } : {}) } : {}),
    limits: limitsForPrompt(i.limits),
  };
}

/** The numbers of a text, as the digits written ("12x35" has 12 and 35). */
const numbers = (text: string): string[] => text.match(/\d+(?:\.\d+)?/g) ?? [];

export const reviewSessionJob: JobDef<ReviewInput, ReviewDraft> = {
  name: "review_session",
  description: "The coach's debrief after a finished session: an evaluation in a human voice against the plan, the program and the goals, and one question for the person.",
  fallbackDescription: "No review: the message is empty and nothing is stored.",
  json: true,
  maxTokens: 1200,
  output: ReviewDraftSchema,
  // The model must not do arithmetic: a number in the message or the question that is not in the data is refused, and the model is told to try again.
  check: (out, i) => {
    const known = new Set(numbers(JSON.stringify(reviewData(i))));
    const bad = numbers(`${out.message} ${out.question?.text ?? ""}`).find((n) => !known.has(n));
    return bad === undefined ? null : `message: the number ${bad} is not in facts; use only the numbers of facts as they are`;
  },
  build: (i) => ({
    system: systemPrompt("review_session", ROLE, SHAPE),
    messages: [{ role: "user", content: dataPrompt("Debrief this session.", reviewData(i)) }],
  }),
  fallback: () => ({ message: "" }),
};
