import type { ContextItem, Goal, PlanDraft, Session } from "../../schema";
import { rulesPlan } from "../../rules/planner";
import { rulesPredictions } from "../../rules/predictions";
import { rulesReview } from "../../rules/review";
import type { DashboardInput } from "./buildDashboard";
import type { PlanInput } from "./planSession";
import type { PredictInput } from "./predictActivity";
import type { ReviewInput } from "./reviewSession";

/**
 * Bounded model input (ADR-012): a job sends the model only recent history.
 * Code that computes numbers or applies limits (rules, applyPlanLimits, resolveDashboard)
 * still reads the FULL history. These builders take the full history, oldest first,
 * and return the bounded input.
 */
export const PLAN_RECENT_OF_TYPE = 6;
export const PLAN_RECENT_ANY = 6;
export const REVIEW_RECENT_OF_TYPE = 6;
export const PREDICTIONS_RECENT = 30;
export const DASHBOARD_RECENT = 30;

const lastN = <T>(xs: T[], n: number): T[] => (n <= 0 ? [] : xs.slice(-n));

/** Plan for type T: the last 6 of type T plus the last 6 of any kind, deduplicated, oldest first. */
export function boundedPlanSessions(all: Session[], type: string): Session[] {
  const ofType = lastN(all.filter((s) => s.type === type), PLAN_RECENT_OF_TYPE);
  const any = lastN(all, PLAN_RECENT_ANY);
  const ids = new Set([...ofType, ...any].map((s) => s.id));
  return all.filter((s) => ids.has(s.id));
}

export function buildPlanInput(all: Session[], goals: Goal[], context: ContextItem[], type: string): PlanInput {
  const rules: PlanDraft = rulesPlan(all, type);
  return { type, sessions: boundedPlanSessions(all, type), goals, context, rules };
}

export function buildPredictInput(all: Session[], goals: Goal[], now: number): PredictInput {
  return { sessions: lastN(all, PREDICTIONS_RECENT), goals, now, rules: rulesPredictions(all, now) };
}

export function buildDashboardInput(all: Session[], goals: Goal[], context: ContextItem[], days: 7 | 30): DashboardInput {
  return { days, sessions: lastN(all, DASHBOARD_RECENT), goals, context };
}

/** Review: the session plus the last 6 of the same type before it, oldest first. */
export function buildReviewInput(all: Session[], session: Session): ReviewInput {
  const before = all.filter((s) => s.id !== session.id && s.kind === session.kind && s.type === session.type && s.endedAt <= session.endedAt);
  return { session, sessions: [...lastN(before, REVIEW_RECENT_OF_TYPE), session], rules: rulesReview(all, session) };
}
