import type { JobDef } from "../runJob";
import { dataPrompt, systemPrompt } from "../promptRules";
import { previousOfType } from "../../rules/review";
import { type ReviewDraft, ReviewDraftSchema, type Session } from "../../schema";
import { logForPrompt } from "./shared";

export interface ReviewInput {
  session: Session;
  /** The session plus the recent sessions of the same activity and focus before it, oldest first (bounded, see inputs.ts). */
  sessions: Session[];
  /** Plain-code review, computed by the caller from the FULL history. */
  rules: ReviewDraft;
}

export const reviewSessionJob: JobDef<ReviewInput, ReviewDraft> = {
  name: "review_session",
  description: "End-of-session summary and guidance: what changed versus the previous session of that activity and focus.",
  fallbackDescription: "Set counts and top sets compared with the previous session of that type.",
  json: true,
  maxTokens: 1500,
  output: ReviewDraftSchema,
  build: (i) => ({
    system: systemPrompt("review_session", "Review the finished session against the previous one of the same activity and focus. Mention only differences visible in the data (sets, reps, weights, duration). Add one practical next-session pointer. Max 400 characters for the summary, at most 5 short change lines.", `{"summary": string (max 400 chars), "changes": string[] (max 5)}`),
    messages: [{ role: "user", content: dataPrompt("Review this session.", { session: logForPrompt([i.session], 1)[0], previousOfSameType: (() => { const p = previousOfType(i.sessions, i.session); return p ? logForPrompt([p], 1)[0] : null; })(), recentSameType: logForPrompt(i.sessions.filter((x) => x.id !== i.session.id), 6) }) }],
  }),
  fallback: (i) => i.rules,
};
