import { z } from "zod";
import type { JobDef } from "../runJob";
import { LIMITS_RULE, dataPrompt, systemPrompt } from "../promptRules";
import { avoidedInPlan, dropAvoided } from "../../rules/limits";
import { type ContextItem, type Goal, type Limit, type PlanDraft, PlanDraftSchema, type Session } from "../../schema";
import { TIME_RULE, contextForPrompt, goalsForPrompt, limitsForPrompt, logForPrompt } from "./shared";

/**
 * `sessions` is the bounded recent history that goes to the model (see inputs.ts).
 * `rules` is the plain-code plan, computed by the caller from the FULL history.
 */
export interface PlanInput {
  /** The activity to plan a session with sets for ("Gym", "Home", ...), as the log spells it. */
  activity: string;
  /** The focus of that session ("Upper", "Quick", ...), when it has one. */
  focus?: string;
  sessions: Session[];
  goals: Goal[];
  context: ContextItem[];
  /** Non-cleared limits. Never holds records. */
  limits: Limit[];
  rules: PlanDraft;
}

const SHAPE = `{"rationale": string (max 200 chars), "exercises": [{"name": string, "sets": [{"reps": int, "kg": number, "max": boolean}], "note"?: string (max 120 chars)} | {"name": string, "measure": "time", "sets": [{"minutes": number}], "note"?: string (max 120 chars)}]}  // at most 12 exercises, at most 10 sets each. ${TIME_RULE}`;

export const planSessionJob: JobDef<PlanInput, PlanDraft> = {
  name: "plan_session",
  description: "Proposes the next session with sets for one activity (and focus) from the log, active goals and active context notes (equipment and preferences).",
  fallbackDescription: "Repeats the user's last session of that activity and focus with its last sets; an empty plan if there is none (no starter template).",
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
      "You plan the next session for one person: a session with sets for one activity. The activity is whatever the user calls it (it may be done at a gym, at home or elsewhere); do not assume a gym or its equipment. Prefer progression the log supports (small weight or rep steps), keep to exercises they already do unless a goal calls for more, and respect the context notes as equipment and training preferences (for example only dumbbells at home, lighter or skipped exercises). If the log has no session of this activity, propose a short simple plan from the goals and notes. Do not exceed 1.25 times the heaviest weight ever logged for an exercise. " + LIMITS_RULE,
      SHAPE,
    ),
    messages: [
      {
        role: "user",
        content: dataPrompt(`Plan the next session with sets for ${i.activity}${i.focus ? `, focus ${i.focus}` : ""}.`, {
          activity: i.activity,
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
