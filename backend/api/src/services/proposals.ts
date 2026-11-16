import { randomUUID } from "node:crypto";
import { buildDashboardJob, planSessionJob, predictActivityJob, reviewSessionJob } from "../ai/jobs";
import type { AiRunner } from "../ai/run-job";
import { resolveDashboard, rulesSpec } from "../rules/dashboard";
import { applyPlanLimits } from "../rules/planner";
import { rulesPredictions } from "../rules/predictions";
import { truncate } from "../rules/util";
import type { Repositories } from "../repositories/types";
import type { Dashboard, DashboardSpec, Plan, Prediction, Review } from "../schema";

export const PLAN_BUDGET_MS = 8_000;

/** Generates, stores and serves AI proposals (plans, predictions, dashboard layouts, reviews). */
export function createProposalService(repos: Repositories, ai: AiRunner, now: () => number) {
  const svc = {
    async generatePlan(type: string, budgetMs?: number): Promise<Plan> {
      const sessions = repos.sessions.list();
      const r = await ai.run(planSessionJob, { type, sessions, goals: repos.goals.list(), context: repos.context.list() }, { timeoutMs: budgetMs });
      const limited = applyPlanLimits(r.value, sessions);
      const plan: Plan = {
        id: randomUUID(),
        type,
        createdAt: now(),
        source: r.path === "ai" ? "ai" : "rules",
        rationale: truncate(limited.rationale, 200),
        exercises: limited.exercises.map((e) => ({ ...e, ...(e.note ? { note: truncate(e.note, 120) } : {}) })),
      };
      return repos.plans.put(plan);
    },

    async nextPlan(type: string): Promise<Plan> {
      return repos.plans.get(type) ?? svc.generatePlan(type, PLAN_BUDGET_MS);
    },

    async refreshPredictions(): Promise<Prediction[]> {
      const r = await ai.run(predictActivityJob, { sessions: repos.sessions.list(), goals: repos.goals.list(), now: now() });
      repos.predictions.put(r.value.predictions);
      return r.value.predictions;
    },

    /** Stored proposal, else rules answer (never waits for AI). */
    predictions(): Prediction[] {
      return repos.predictions.get() ?? rulesPredictions(repos.sessions.list(), now());
    },

    async refreshDashboard(days: 7 | 30): Promise<DashboardSpec> {
      const goals = repos.goals.list();
      const r = await ai.run(buildDashboardJob, { days, sessions: repos.sessions.list(), goals, context: repos.context.list() });
      const ids = new Set(goals.map((g) => g.id));
      const modules = r.value.modules.filter((m) => m.type !== "goal_progress" || ids.has(m.goalId));
      const spec: DashboardSpec = { source: r.path === "ai" ? "ai" : "rules", modules };
      repos.dashboards.put(days, spec);
      return spec;
    },

    dashboard(days: 7 | 30): { dashboard: Dashboard; stored: boolean } {
      const goals = repos.goals.list();
      const stored = repos.dashboards.get(days);
      const spec = stored ?? rulesSpec(goals);
      return { dashboard: resolveDashboard(spec, repos.sessions.list(), goals, days, now()), stored: !!stored };
    },

    async reviewSession(sessionId: string): Promise<Review | null> {
      const session = repos.sessions.get(sessionId);
      if (!session) return null;
      const r = await ai.run(reviewSessionJob, { session, sessions: repos.sessions.list() });
      return repos.reviews.put({ sessionId, source: r.path === "ai" ? "ai" : "rules", summary: truncate(r.value.summary, 400), changes: r.value.changes.slice(0, 5) });
    },
  };
  return svc;
}

export type ProposalService = ReturnType<typeof createProposalService>;
