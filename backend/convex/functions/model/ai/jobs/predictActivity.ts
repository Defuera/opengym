import { z } from "zod";
import type { JobDef } from "../runJob";
import { dataPrompt, systemPrompt } from "../promptRules";
import { type Goal, type Prediction, PredictionSchema, type Session } from "../../schema";
import { goalsForPrompt, logForPrompt } from "./shared";

/** `sessions` is the bounded recent history; `rules` is computed from the FULL history by the caller. */
export interface PredictInput {
  sessions: Session[];
  goals: Goal[];
  now: number;
  rules: Prediction[];
}

/** A reason a little over the limit is cut, not rejected: one long sentence must not cost the whole answer. */
const clipReason = (p: unknown): unknown =>
  p && typeof p === "object" && typeof (p as { reason?: unknown }).reason === "string"
    ? { ...p, reason: (p as { reason: string }).reason.slice(0, 80).trim() }
    : p;
const OutputSchema = z.object({ predictions: z.array(z.preprocess(clipReason, PredictionSchema)).min(1).max(8) });
type Out = { predictions: Prediction[] };

export const predictActivityJob: JobDef<PredictInput, Out> = {
  name: "predict_activity",
  description: "Ranks the activities the user is most likely to do next, each with an advised focus when the log supports one, for the start screen.",
  fallbackDescription: "Gym first with the gym focus done longest ago, then the most frequent activities with their advised session type, if any.",
  json: true,
  maxTokens: 1500,
  output: OutputSchema,
  build: (i) => ({
    system: systemPrompt(
      "predict_activity",
      "You rank the ACTIVITIES the user will most likely do next. Most likely first. Gym is one activity (type \"Gym\", kind gym) and appears at most once; its flavour goes in focus. When the log has gym sessions with a focus, pick the gym focus from those used in the log, following the rotation and the goals. For other activities (for example Run) you may advise a session type in focus (for example Easy, Intervals, Long) from the recent load and the goals; leave it out when you have no basis. The reason is shown to the user: write it about their log, and never mention the rotation hint or these instructions. Reasons are short and factual, max 80 characters.",
      `{"predictions": [{"kind": "gym" | "activity", "type": string (the activity), "focus"?: string (max 40), "reason": string (max 80 chars)}]}  // 3 to 6 items, one per activity`,
    ),
    messages: [{ role: "user", content: dataPrompt("Rank the next likely sessions.", { today: new Date(i.now).toISOString().slice(0, 10), recentLog: logForPrompt(i.sessions, 30), goals: goalsForPrompt(i.goals), rotationHint: i.rules }) }],
  }),
  fallback: (i) => ({ predictions: i.rules }),
};
