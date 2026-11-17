import { z } from "zod";
import type { JobDef } from "../runJob";
import { LIMITS_RULE, dataPrompt, systemPrompt } from "../promptRules";
import { avoidedInPlan, dropAvoided } from "../../rules/limits";
import { type ContextItem, type Goal, type Limit, type PlanDraft, PlanDraftSchema, type Session } from "../../schema";
import { contextForPrompt, goalsForPrompt, limitsForPrompt, logForPrompt } from "./shared";

/**
 * `sessions` is the bounded recent history that goes to the model (see inputs.ts).
 * `rules` is the plain-code plan, computed by the caller from the FULL history.
 */
export interface PlanInput {
  /** The gym focus to plan ("Upper", "Legs", ...). The activity is always Gym. */
  focus: string;
  sessions: Session[];
  goals: Goal[];
  context: ContextItem[];
  /** Non-cleared limits. Never holds records. */
  limits: Limit[];
  rules: PlanDraft;
}

const SHAPE = `{"rationale": string (max 200 chars), "exercises": [{"name": string, "sets": [{"reps": int, "kg": number, "max": boolean}], "note"?: string (max 120 chars)}]}  // at most 12 exercises, at most 10 sets each`;

export const planSessionJob: JobDef<PlanInput, PlanDraft> = {
  name: "plan_session",
  description: "Proposes the next gym session of a given focus from the log, active goals and active context notes.",
  fallbackDescription: "Repeats the last session of that focus with its last sets; starter template (bench press 6x20, 6x40, 6x60, 1x60 max) if there is none.",
  json: true,
  // Reasoning tokens count against this limit on OpenAI; 1500 gave empty answers with real history.
  maxTokens: 4000,
  output: PlanDraftSchema as z.ZodType<PlanDraft>,
  // Hard check (ADR-015): an exercise named by an avoid rule makes the plan invalid, like a shape error.
  check: (plan, i) => {
    const hit = avoidedInPlan(plan, i.limits);
    return hit ? `exercises: "${hit}" is marked avoid` : null;
  },
  build: (i) => ({
    system: systemPrompt(
      "plan_session",
      "You plan the next gym session for one person. Prefer progression the log supports (small weight or rep steps), keep to exercises they already do unless a goal calls for more, and respect active context notes as training preferences (for example lighter or skipped exercises). Do not exceed 1.25 times the heaviest weight ever logged for an exercise. " + LIMITS_RULE,
      SHAPE,
    ),
    messages: [
      {
        role: "user",
        content: dataPrompt(`Plan the next gym session with focus ${i.focus}.`, {
          focus: i.focus,
          recentLog: logForPrompt(i.sessions),
          goals: goalsForPrompt(i.goals.filter((g) => g.status === "active")),
          context: contextForPrompt(i.context),
          limits: limitsForPrompt(i.limits),
          suggestedStart: i.rules,
        }),
      },
    ],
  }),
  fallback: (i) => dropAvoided(i.rules, i.limits),
};
