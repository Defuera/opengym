import { applyPlanLimits } from "./rules/planner";
import { truncate } from "./rules/util";
import { dropAvoided } from "./rules/limits";
import type { Limit, PlanDraft, ReviewDraft, Session } from "./schema";

/**
 * Safety limits and truncations for a plan draft (ADR-004). `allSessions` must be the FULL history:
 * the weight cap uses the heaviest weight ever logged, not just what the model saw.
 */
export function finalizePlan(draft: PlanDraft, allSessions: Session[], limits: Limit[] = []): PlanDraft {
  const limited = applyPlanLimits(dropAvoided(draft, limits), allSessions);
  return {
    rationale: truncate(limited.rationale, 200),
    exercises: limited.exercises.map((e) => ({ ...e, ...(e.note ? { note: truncate(e.note, 120) } : {}) })),
  };
}

export function finalizeReview(draft: ReviewDraft): ReviewDraft {
  return { summary: truncate(draft.summary, 400), changes: draft.changes.slice(0, 5) };
}
