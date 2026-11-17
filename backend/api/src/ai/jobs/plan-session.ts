import { z } from "zod";
import type { JobDef } from "../run-job";
import { dataPrompt, systemPrompt } from "../prompt-rules";
import { rulesPlan } from "../../rules/planner";
import { type ContextItem, type Goal, type PlanDraft, PlanDraftSchema, type Session } from "../../schema";
import { contextForPrompt, goalsForPrompt, logForPrompt } from "./shared";

export interface PlanInput {
  type: string;
  sessions: Session[];
  goals: Goal[];
  context: ContextItem[];
}

const SHAPE = `{"rationale": string (max 200 chars), "exercises": [{"name": string, "sets": [{"reps": int, "kg": number, "max": boolean}], "note"?: string (max 120 chars)}]}  // at most 12 exercises, at most 10 sets each`;

export const planSessionJob: JobDef<PlanInput, PlanDraft> = {
  name: "plan_session",
  description: "Proposes the next session of a given type from the log, active goals and active context notes.",
  fallbackDescription: "Repeats the last session of that type with its last sets; starter template (bench press 6x20, 6x40, 6x60, 1x60 max) if there is none.",
  json: true,
  maxTokens: 1500,
  output: PlanDraftSchema as z.ZodType<PlanDraft>,
  build: (i) => ({
    system: systemPrompt(
      "plan_session",
      "You plan the next gym session for one person. Prefer progression the log supports (small weight or rep steps), keep to exercises they already do unless a goal calls for more, and respect active context notes as training preferences (for example lighter or skipped exercises). Do not exceed 1.25 times the heaviest weight ever logged for an exercise.",
      SHAPE,
    ),
    messages: [
      {
        role: "user",
        content: dataPrompt(`Plan the next ${i.type} session.`, {
          type: i.type,
          recentLog: logForPrompt(i.sessions),
          goals: goalsForPrompt(i.goals.filter((g) => g.status === "active")),
          context: contextForPrompt(i.context),
          suggestedStart: rulesPlan(i.sessions, i.type),
        }),
      },
    ],
  }),
  fallback: (i) => rulesPlan(i.sessions, i.type),
};
