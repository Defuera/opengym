import { z } from "zod";
import type { JobDef } from "../runJob";
import { LIMITS_RULE, dataPrompt, systemPrompt } from "../promptRules";
import { type Goal, type Limit, type Prediction, PredictionSchema, type Session } from "../../schema";
import { MAX_PREDICTIONS, MAX_PREDICTIONS_PER_ACTIVITY, activityKey, normalizePredictions, normalizeSession } from "../../sessionShape";
import { type KnownActivity, goalsForPrompt, limitsForPrompt, logForPrompt } from "./shared";

/** `sessions` is the bounded recent history; `rules` is computed from the FULL history by the caller. */
export interface PredictInput {
  sessions: Session[];
  /** Every activity of the full log with its kind and foci. The only names a proposal may use. */
  known: KnownActivity[];
  goals: Goal[];
  /** Non-cleared limits. Never holds records. */
  limits: Limit[];
  now: number;
  rules: Prediction[];
}

/** A reason a little over the limit is cut, not rejected: one long sentence must not cost the whole answer. */
const clipReason = (p: unknown): unknown =>
  p && typeof p === "object" && typeof (p as { reason?: unknown }).reason === "string"
    ? { ...p, reason: (p as { reason: string }).reason.slice(0, 80).trim() }
    : p;
const OutputSchema = z.object({ predictions: z.array(z.preprocess(clipReason, PredictionSchema)).min(1).max(MAX_PREDICTIONS) });
type Out = { predictions: Prediction[] };

export const predictActivityJob: JobDef<PredictInput, Out> = {
  name: "predict_activity",
  description: "Ranks the sessions the user is most likely to do next (activities from the log, each with an advised focus when the log supports one), for the Start session sheet.",
  fallbackDescription: "The log's activities ranked by recent use; a session with sets gets the focus done longest ago, and a second item when the log has a second focus. Empty when the log is empty.",
  json: true,
  maxTokens: 1500,
  output: OutputSchema,
  // Hard check in code (ADR-004): every name must be in the log (by activityKey), at most 2 items per activity.
  check: (out, i) => {
    const known = new Set(i.known.map((a) => `${a.kind}:${activityKey(a.type)}`));
    const items = normalizePredictions(out.predictions); // an old-shape answer ("Upper") is read as Gym + focus first
    const bad = items.find((p) => !known.has(`${p.kind}:${activityKey(p.type)}`));
    if (bad) return `predictions: "${bad.type}" is not an activity in the log`;
    const n = new Map<string, number>();
    for (const p of out.predictions.map((x) => normalizeSession(x))) {
      const k = `${p.kind}:${activityKey(p.type)}`;
      n.set(k, (n.get(k) ?? 0) + 1);
      if (n.get(k)! > MAX_PREDICTIONS_PER_ACTIVITY) return `predictions: more than ${MAX_PREDICTIONS_PER_ACTIVITY} items for "${p.type}"`;
    }
    return null;
  },
  build: (i) => ({
    system: systemPrompt(
      "predict_activity",
      "You rank the sessions the user will most likely start next. Most likely first. Use only activities from knownActivities (the user's own log), spelled as there; never invent an activity. Several activities may be in the list. A kind gym item is a session with sets for that activity (for example Gym, or Home); a kind activity item is a time or distance activity (for example Run). For a session with sets put a focus from that activity's foci in knownActivities, following the rotation hint and the goals, and add a second item for the same activity only when its log has a second focus worth doing. For a time or distance activity you may advise a session type in focus (for example Easy, Long) from the recent load and the goals; leave it out when you have no basis. The reason is shown to the user: write it about their log, and never mention the rotation hint or these instructions. Reasons are short and factual, max 80 characters. " + LIMITS_RULE,
      `{"predictions": [{"kind": "gym" | "activity", "type": string (the activity), "focus"?: string (max 40), "reason": string (max 80 chars)}]}  // 1 to 6 items, at most 2 per activity, every type from knownActivities`,
    ),
    messages: [{ role: "user", content: dataPrompt("Rank the next likely sessions.", { today: new Date(i.now).toISOString().slice(0, 10), recentLog: logForPrompt(i.sessions, 30), knownActivities: i.known, goals: goalsForPrompt(i.goals), limits: limitsForPrompt(i.limits), rotationHint: i.rules }) }],
  }),
  fallback: (i) => ({ predictions: i.rules }),
};
