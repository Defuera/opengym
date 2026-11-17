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

const OutputSchema = z.object({ predictions: z.array(PredictionSchema).min(1).max(8) });
type Out = { predictions: Prediction[] };

export const predictActivityJob: JobDef<PredictInput, Out> = {
  name: "predict_activity",
  description: "Ranks what the user is most likely to do next (gym types and activities) for the start screen.",
  fallbackDescription: "Rotation: the gym type done longest ago first, then the most frequent activities.",
  json: true,
  maxTokens: 1500,
  output: OutputSchema,
  build: (i) => ({
    system: systemPrompt(
      "predict_activity",
      "You rank what the user will most likely do next. Most likely first. Gym types are usually Push, Pull, Legs but follow the log. Reasons are short and factual, max 80 characters.",
      `{"predictions": [{"kind": "gym" | "activity", "type": string, "reason": string (max 80 chars)}]}  // 3 to 6 items`,
    ),
    messages: [{ role: "user", content: dataPrompt("Rank the next likely sessions.", { today: new Date(i.now).toISOString().slice(0, 10), recentLog: logForPrompt(i.sessions, 30), goals: goalsForPrompt(i.goals), baseline: i.rules }) }],
  }),
  fallback: (i) => ({ predictions: i.rules }),
};
