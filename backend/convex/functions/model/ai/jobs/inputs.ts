import { dropAvoided } from "../../rules/limits";
import type { ContextItem, Goal, Limit, PlanDraft, Session } from "../../schema";
import { activityKey } from "../../sessionShape";
import { fociByDue, loggedActivities } from "../../rules/foci";
import { rulesPlan } from "../../rules/planner";
import { rulesReview } from "../../rules/review";
import type { DashboardInput } from "./buildDashboard";
import { coachPicture } from "./coachPicture";
import type { PlanInput } from "./planSession";
import type { ReviewInput } from "./reviewSession";
import type { KnownActivity } from "./shared";

/**
 * Bounded model input (ADR-012): a job sends the model only recent history.
 * Code that computes numbers or applies limits (rules, applyPlanLimits, resolveDashboard)
 * still reads the FULL history. These builders take the full history, oldest first,
 * and return the bounded input.
 */
export const PLAN_RECENT_OF_TYPE = 6;
export const PLAN_RECENT_ANY = 6;
export const REVIEW_RECENT_OF_TYPE = 6;
export const DASHBOARD_RECENT = 30;

const lastN = <T>(xs: T[], n: number): T[] => (n <= 0 ? [] : xs.slice(-n));

/**
 * Plan for an activity and focus: the last 6 sessions with sets of that activity (and focus, when one is given)
 * plus the last 6 of any kind, deduplicated, oldest first.
 */
export function boundedPlanSessions(all: Session[], activity: string, focus?: string): Session[] {
  const key = activityKey(activity);
  const fk = focus === undefined ? null : activityKey(focus);
  const ofType = lastN(all.filter((s) => s.kind === "gym" && activityKey(s.type) === key && (fk === null || activityKey(s.focus ?? "") === fk)), PLAN_RECENT_OF_TYPE);
  const any = lastN(all, PLAN_RECENT_ANY);
  const ids = new Set([...ofType, ...any].map((s) => s.id));
  return all.filter((s) => ids.has(s.id));
}

/** `limits` must be the non-cleared limits. The rules plan already drops exercises an avoid rule names. */
export function buildPlanInput(all: Session[], goals: Goal[], context: ContextItem[], activity: string, focus: string | undefined, limits: Limit[] = []): PlanInput {
  const rules: PlanDraft = dropAvoided(rulesPlan(all, activity, focus), limits);
  return { activity, ...(focus !== undefined ? { focus } : {}), sessions: boundedPlanSessions(all, activity, focus), goals, context, limits, rules };
}

export const KNOWN_ACTIVITIES_MAX = 30;
export const KNOWN_FOCI_MAX = 8;

/** The vocabulary of the log, for prompts: every activity with its kind and foci. Most used first, bounded. */
export function knownActivities(all: Session[], now: number): KnownActivity[] {
  return loggedActivities(all, now)
    .slice(0, KNOWN_ACTIVITIES_MAX)
    .map((a) => ({ type: a.name, kind: a.kind, foci: (a.kind === "gym" ? fociByDue(all, a.name) : activityFoci(all, a.key)).slice(0, KNOWN_FOCI_MAX) }));
}

function activityFoci(all: Session[], key: string): string[] {
  const seen = new Map<string, string>();
  for (const s of all) if (s.kind === "activity" && activityKey(s.type) === key && s.focus) seen.set(activityKey(s.focus), s.focus.trim());
  return [...seen.values()];
}

export function buildDashboardInput(all: Session[], goals: Goal[], context: ContextItem[], days: 7 | 30): DashboardInput {
  return { days, sessions: lastN(all, DASHBOARD_RECENT), goals, context };
}

/**
 * Review: the session, the last 6 of the same activity and focus before it (oldest first), and, when the caller gives the goals
 * and notes, the picture of the person as it was just before the session started (so "last sets" never holds the session itself).
 */
export function buildReviewInput(all: Session[], session: Session, limits: Limit[] = [], about?: { goals: Goal[]; context: ContextItem[] }): ReviewInput {
  const before = all.filter((s) => s.id !== session.id && s.kind === session.kind && s.type === session.type && s.focus === session.focus && s.endedAt <= session.endedAt);
  const earlier = all.filter((s) => s.id !== session.id && s.endedAt <= session.startedAt);
  const picture = about ? coachPicture(earlier, [...about.goals].sort((x, y) => x.createdAt - y.createdAt), about.context, limits, [], session.startedAt) : undefined;
  return { session, sessions: [...lastN(before, REVIEW_RECENT_OF_TYPE), session], limits, ...(picture ? { picture } : {}), rules: rulesReview(all, session) };
}
