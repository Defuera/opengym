import { v } from "convex/values";
import { query } from "../_generated/server";
import type { DatabaseReader } from "../_generated/server";
import type { Session } from "../model/schema";
import { requireToken } from "../lib/auth";
import { allSessions, planByFocus, storedPredictions } from "../lib/db";
import { finalizePlan } from "../model/proposals";
import { gymFociByDue } from "../model/rules/foci";
import { rulesPlan } from "../model/rules/planner";
import { GYM_TYPE } from "../model/schema/common";

/**
 * The next gym plan for a focus. Never calls the AI (ADR-003): switching focus reads a stored plan.
 * `focus` is optional. With none, the plan is for the advised focus (the first gym item of the predictions).
 * `type` is the legacy name of `focus` (an older app build sends it); it is read the same way.
 * Returns the stored plan (`stored: true`, source "ai", or "rules" if the job fell back).
 * With no stored plan yet it returns the rules plan computed here (`stored: false`, source "rules");
 * the app gets the AI plan through its live subscription once the job has run.
 */
export const next = query({
  args: { token: v.string(), focus: v.optional(v.string()), type: v.optional(v.string()) },
  handler: async (ctx, { token, focus: given, type }) => {
    requireToken(token);
    const sessions = await allSessions(ctx);
    const wanted = given ?? (type && type !== GYM_TYPE ? type : undefined);
    const focus = wanted ?? (await advisedFocus(ctx, sessions));
    const doc = await planByFocus(ctx, focus);
    if (doc) {
      const { _id, createdAt, source, rationale, exercises } = doc;
      return { plan: { id: _id as string, type: GYM_TYPE, focus, createdAt, source, rationale, exercises }, stored: true };
    }
    const draft = finalizePlan(rulesPlan(sessions, focus), sessions);
    return { plan: { id: `rules:${focus}`, type: GYM_TYPE, focus, createdAt: Date.now(), source: "rules" as const, ...draft }, stored: false };
  },
});

async function advisedFocus(ctx: { db: DatabaseReader }, sessions: Session[]): Promise<string> {
  const stored = await storedPredictions(ctx);
  const fromStored = stored?.items.find((p) => p.kind === "gym")?.focus;
  return fromStored ?? gymFociByDue(sessions)[0]!;
}
