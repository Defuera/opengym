import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { allSessions } from "../lib/db";
import { finalizePlan } from "../model/proposals";
import { rulesPlan } from "../model/rules/planner";

/**
 * The next plan for a session type. Never calls the AI.
 * Returns the stored plan (`stored: true`, source "ai", or "rules" if the job fell back).
 * With no stored plan yet it returns the rules plan computed here (`stored: false`, source "rules");
 * the app gets the AI plan through its live subscription once the job has run.
 */
export const next = query({
  args: { token: v.string(), type: v.string() },
  handler: async (ctx, { token, type }) => {
    requireToken(token);
    const doc = await ctx.db.query("plans").withIndex("by_type", (q) => q.eq("type", type)).unique();
    if (doc) {
      const { _id, type: t, createdAt, source, rationale, exercises } = doc;
      return { plan: { id: _id as string, type: t, createdAt, source, rationale, exercises }, stored: true };
    }
    const sessions = await allSessions(ctx);
    const draft = finalizePlan(rulesPlan(sessions, type), sessions);
    return { plan: { id: `rules:${type}`, type, createdAt: Date.now(), source: "rules" as const, ...draft }, stored: false };
  },
});
