import type { JobDef } from "../run-job";
import { dataPrompt, systemPrompt } from "../prompt-rules";
import { previousOfType, rulesReview } from "../../rules/review";
import { type ReviewDraft, ReviewDraftSchema, type Session } from "../../schema";
import { logForPrompt } from "./shared";

export interface ReviewInput {
  session: Session;
  /** All sessions, oldest first, including this one. */
  sessions: Session[];
}

export const reviewSessionJob: JobDef<ReviewInput, ReviewDraft> = {
  name: "review_session",
  description: "End-of-session summary and guidance: what changed versus the previous session of that type.",
  fallbackDescription: "Set counts and top sets compared with the previous session of that type.",
  json: true,
  maxTokens: 500,
  output: ReviewDraftSchema,
  build: (i) => ({
    system: systemPrompt("review_session", "Review the finished session against the previous one of the same type. Mention only differences visible in the data (sets, reps, weights, duration). Add one practical next-session pointer. Max 400 characters for the summary, at most 5 short change lines.", `{"summary": string (max 400 chars), "changes": string[] (max 5)}`),
    messages: [{ role: "user", content: dataPrompt("Review this session.", { session: logForPrompt([i.session], 1)[0], previousOfSameType: (() => { const p = previousOfType(i.sessions, i.session); return p ? logForPrompt([p], 1)[0] : null; })() }) }],
  }),
  fallback: (i) => rulesReview(i.sessions, i.session),
};
