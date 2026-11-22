import type { JobDef } from "../runJob";
import { LIMITS_RULE, dataPrompt, systemPrompt } from "../promptRules";
import { previousOfType } from "../../rules/review";
import { type Limit, type ReviewDraft, ReviewDraftSchema, type Session } from "../../schema";
import { limitsForPrompt, logForPrompt } from "./shared";

export interface ReviewInput {
  session: Session;
  /** The session plus the recent sessions of the same activity and focus before it, oldest first (bounded, see inputs.ts). */
  sessions: Session[];
  /** Non-cleared limits. Never holds records. */
  limits: Limit[];
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
    system: systemPrompt("review_session", "Review the finished session against the previous one of the same activity and focus. Mention only differences visible in the data (sets, reps, weights, duration). An exercise may carry commentFromThePerson, written during the session: take it into account and answer to it when it matters. Add one practical next-session pointer. Max 400 characters for the summary, at most 5 short change lines. " + LIMITS_RULE, `{"summary": string (max 400 chars), "changes": string[] (max 5)}`),
    messages: [{ role: "user", content: dataPrompt("Review this session.", { session: logForPrompt([i.session], 1)[0], previousOfSameType: (() => { const p = previousOfType(i.sessions, i.session); return p ? logForPrompt([p], 1)[0] : null; })(), recentSameType: logForPrompt(i.sessions.filter((x) => x.id !== i.session.id), 6), limits: limitsForPrompt(i.limits) }) }],
  }),
  fallback: (i) => i.rules,
};
