import type { JobDef } from "../runJob";
import { dataPrompt, systemPrompt } from "../promptRules";
import { rulesSpec } from "../../rules/dashboard";
import { type ContextItem, type DashboardSpecDraft, DashboardSpecDraftSchema, type Goal, type Session } from "../../schema";
import { contextForPrompt, goalsForPrompt, logForPrompt } from "./shared";

export interface DashboardInput {
  days: 7 | 30;
  sessions: Session[];
  goals: Goal[];
  context: ContextItem[];
}

const SHAPE = `{"modules": [ // at most 10, in display order
  {"type": "stat", "which": "sessions" | "active_days" | "sets" | "top_set"},
  {"type": "goal_progress", "goalId": string  /* an id from the goals list */},
  {"type": "trend", "exercise"?: string /* an exercise from the log */},
  {"type": "consistency"},
  {"type": "recent_sessions", "limit"?: int 1..10},
  {"type": "note", "text": string (max 200 chars)}
]}`;

export const buildDashboardJob: JobDef<DashboardInput, DashboardSpecDraft> = {
  name: "build_dashboard",
  description: "Chooses which dashboard modules to show, in what order, and their parameters. Code computes every number.",
  fallbackDescription: "Fixed layout: sessions, active days, top set of the most-trained exercise, one goal_progress per active goal, recent sessions.",
  json: true,
  maxTokens: 2000,
  output: DashboardSpecDraftSchema,
  build: (i) => ({
    system: systemPrompt(
      "build_dashboard",
      "You pick the layout of a training dashboard. You choose module types, order and parameters only; never write numbers or statistics yourself, code fills them in. A note module may hold one short motivating sentence about training, with no figures you were not given.",
      SHAPE,
    ),
    messages: [{ role: "user", content: dataPrompt(`Pick modules for a ${i.days}-day dashboard.`, { days: i.days, recentLog: logForPrompt(i.sessions, 20), goals: goalsForPrompt(i.goals), context: contextForPrompt(i.context) }) }],
  }),
  fallback: (i) => ({ modules: rulesSpec(i.goals).modules }),
};
