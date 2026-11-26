import { applyPlanLimits, fitPlanToMinutes } from "./rules/planner";
import { fociByUse, loggedName } from "./rules/foci";
import { truncate } from "./rules/util";
import { dropAvoided } from "./rules/limits";
import { activityKey } from "./sessionShape";
import { REVIEW_MESSAGE_MAX, type Limit, type PlanDraft, type ReviewDraft, type Session, type StartProposal } from "./schema";

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

/** The stored shape of a debrief: the message cut to its limit, the answers with ids made here (a1, a2, ...). */
export function finalizeReview(draft: ReviewDraft) {
  const q = draft.question;
  return {
    message: truncate(draft.message, REVIEW_MESSAGE_MAX),
    ...(q ? { question: { text: truncate(q.text, 120), answers: q.answers.slice(0, 4).map((label, i) => ({ id: `a${i + 1}`, label: truncate(label, 24) })) } } : {}),
  };
}

/**
 * Checks in code for a start proposal (ADR-004, ADR-016). The name reuses the log's spelling when the log has the name
 * (matched by activityKey), and so does the focus. A session with sets gets the plan safety limits, the avoid rules and a size that fits the minutes asked for;
 * a time or distance activity has no plan. `allSessions` must be the FULL history.
 */
export function finalizeStartProposal(p: StartProposal, allSessions: Session[], limits: Limit[] = []): StartProposal {
  const asked = p.type.trim().slice(0, 40) || "Gym";
  const type = loggedName(allSessions, asked, p.kind) ?? loggedName(allSessions, asked) ?? asked;
  // A focus the log already has keeps the log's spelling ("upper" -> "Upper"), so one focus stays one name.
  const given = p.focus?.trim().slice(0, 40).trim();
  const focus = given ? (fociByUse(allSessions, type).find((f) => activityKey(f.focus) === activityKey(given))?.focus ?? given) : undefined;
  const reason = p.reason?.trim() ? truncate(p.reason.trim(), 80) : undefined;
  const base = { kind: p.kind, type, ...(focus ? { focus } : {}), ...(p.minutes !== undefined ? { minutes: p.minutes } : {}), ...(reason ? { reason } : {}) };
  if (p.kind === "activity") return base;
  const plan = finalizePlan(p.plan ?? { rationale: "Empty session. Add what you do.", exercises: [] }, allSessions, limits);
  return { ...base, plan: p.minutes !== undefined ? fitPlanToMinutes(plan, p.minutes) : plan };
}
