import type { JobResult } from "./ai/runJob";
import { fallbackProposal, nameFromText } from "./startFallback";
import { finalizeStartProposal } from "./proposals";
import type { StartProposal, Limit, PlanDraft, Session } from "./schema";
import type { KnownActivity } from "./ai/jobs/shared";
import { activityKey } from "./sessionShape";

/** What to store after the build_session job ran: a failed request, or a proposal with the source of its plan. */
export type StartOutcome = { failed: true } | { failed: false; source: "ai" | "rules"; proposal: StartProposal };

/**
 * The step after the AI answer in the `build` action: a rebuild (feedback) that did not get an AI answer fails (the rules plan would not respect
 * the feedback); otherwise the AI proposal, or the plain fallback (the rules plan of the log when it has exercises, else an empty plan).
 */
export function startOutcome(r: Pick<JobResult<StartProposal>, "path" | "value">, input: { job: { feedbackFromThePerson?: string[] }; rules: PlanDraft | null; text: string; name: string | null; known: KnownActivity[] }): StartOutcome {
  if (r.path !== "ai" && input.job.feedbackFromThePerson) return { failed: true };
  const plain = fallbackProposal(input);
  const proposal = r.path === "ai" ? r.value : input.rules && input.rules.exercises.length > 0 ? { ...plain, plan: input.rules } : plain;
  return { failed: false, source: r.path === "ai" ? "ai" : "rules", proposal };
}

/**
 * The checks in code before a proposal is stored (the `save` mutation). A given name is fixed: the AI must not rename the session.
 * With no name the type is the coach's name, cut to 40 (finalizeStartProposal keeps the log's spelling). `sessions` is the FULL history.
 */
export function checkedStartProposal(doc: { name?: string; text?: string }, proposal: StartProposal, sessions: Session[], limits: Limit[]): StartProposal {
  const type = doc.name ?? (proposal.type.trim().slice(0, 40).trim() || nameFromText(doc.text ?? ""));
  return finalizeStartProposal({ ...proposal, type }, sessions, limits);
}

/**
 * The place of a proposal (ADR-021): the name the coach gave (an existing place with the same key, else a new one with an empty text),
 * else the place of the newest session of this activity. Null when neither is known.
 */
export function pickPlace<P extends { placeId: string; name: string }>(places: P[], given: string | undefined, lastPlaceId: string | undefined): { place: P } | { newName: string } | null {
  const g = given?.trim();
  if (g) {
    const found = places.find((p) => activityKey(p.name) === activityKey(g));
    return found ? { place: found } : { newName: g };
  }
  const last = lastPlaceId ? places.find((p) => p.placeId === lastPlaceId) : undefined;
  return last ? { place: last } : null;
}
