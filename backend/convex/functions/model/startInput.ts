import type { BuildSessionInput } from "./ai/jobs/buildSession";
import { coachPicture } from "./ai/jobs/coachPicture";
import { knownActivities } from "./ai/jobs/inputs";
import { lastPlaceIdFor } from "./places";
import { dropAvoided } from "./rules/limits";
import { rulesPlan } from "./rules/planner";
import type { ContextItem, Entry, Goal, Limit, PlanDraft, Session } from "./schema";
import { activityKey } from "./sessionShape";

/** What the start request holds (the fields the input reads). */
export interface StartDoc {
  name?: string;
  text?: string;
  feedback?: string[];
  previousPlan?: unknown;
}

/** What the server has read for the request: the FULL history (oldest first), the non-cleared limits, every place. */
export interface StartData {
  sessions: Session[];
  goals: Goal[];
  context: ContextItem[];
  limits: Limit[];
  places: { placeId: string; name: string; text: string }[];
  entries: Entry[];
  now: number;
}

/**
 * Bounded model input for one start request (pure; the Convex query reads the data, the eval runner reads fixtures).
 * `rules` is the plain rules plan of the named activity, for the fallback.
 */
export function buildStartInput(doc: StartDoc, d: StartData) {
  const known = knownActivities(d.sessions, d.now);
  const match = doc.name ? known.find((a) => activityKey(a.type) === activityKey(doc.name!)) : undefined;
  const rules: PlanDraft | null = match?.kind === "gym" ? dropAvoided(rulesPlan(d.sessions, match.type), d.limits) : null;
  // The places the coach knows (ADR-021): all of them, with the one last used for this activity marked. Only places go here, never records.
  const lastPlaceId = doc.name ? lastPlaceIdFor(d.sessions, doc.name) : undefined;
  const placesTheCoachKnows = d.places.map((p) => ({ name: p.name, equipment: p.text, lastUsedForThisActivity: p.placeId === lastPlaceId }));
  const job: BuildSessionInput = {
    name: doc.name ?? null,
    note: doc.name ? (doc.text ?? "") : "",
    ...(doc.name ? {} : { request: doc.text ?? "" }),
    ...(doc.feedback ? { feedbackFromThePerson: doc.feedback, ...(doc.previousPlan ? { previousPlan: doc.previousPlan } : {}) } : {}),
    placesTheCoachKnows,
    picture: coachPicture(d.sessions, [...d.goals].sort((x, y) => x.createdAt - y.createdAt), d.context, d.limits, d.entries, d.now),
    limits: d.limits,
  };
  return { job, known, text: doc.text ?? "", name: doc.name ?? null, rules };
}
