import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { allSessions, planFor, storedPredictions } from "../lib/db";
import { finalizePlan } from "../model/proposals";
import { fociByDue, loggedName } from "../model/rules/foci";
import { rulesPlan } from "../model/rules/planner";
import { GYM_TYPE } from "../model/schema/common";
import { activityKey } from "../model/sessionShape";

/**
 * The next plan for a session with sets of an activity and focus. Never calls the AI (ADR-003): switching reads a stored plan.
 * `activity` is the activity name (default "Gym"; matched by activityKey, shown as the log spells it).
 * `focus` is optional. With none, the plan is for the advised focus: the first stored prediction of that activity, else the focus due in the log, else no focus.
 * `type` is the legacy name of `focus` (an older app build sends it, with the activity Gym); it is read the same way.
 * Returns the stored plan (`stored: true`, source "ai", or "rules" if the job fell back).
 * With no stored plan it returns the rules plan computed here (`stored: false`, source "rules"): the user's own last session of that
 * activity and focus, or an EMPTY plan when there is none (no starter template). The app gets the AI plan through its live
 * subscription once the job has run (plans are precomputed only for the set-based items of the current predictions, max 3).
 */
export const next = query({
  args: { token: v.string(), activity: v.optional(v.string()), focus: v.optional(v.string()), type: v.optional(v.string()) },
  handler: async (ctx, { token, activity: givenActivity, focus: given, type }) => {
    requireToken(token);
    const sessions = await allSessions(ctx);
    const asked = (givenActivity ?? "").trim() || GYM_TYPE;
    const activity = loggedName(sessions, asked, "gym") ?? asked.slice(0, 40);
    const key = activityKey(activity);
    const legacy = givenActivity === undefined && type && activityKey(type) !== activityKey(GYM_TYPE) ? type : undefined;
    const wanted = (given ?? legacy)?.trim() || undefined;
    const stored = await storedPredictions(ctx);
    const focus = wanted ?? stored?.items.find((p) => p.kind === "gym" && activityKey(p.type) === key)?.focus ?? fociByDue(sessions, activity)[0];
    const doc = await planFor(ctx, activity, focus);
    if (doc) {
      const { _id, createdAt, source, rationale, exercises } = doc;
      return { plan: { id: _id as string, type: activity, ...(focus ? { focus } : {}), createdAt, source, rationale, exercises }, stored: true };
    }
    const draft = finalizePlan(rulesPlan(sessions, activity, focus), sessions);
    return { plan: { id: key === activityKey(GYM_TYPE) ? `rules:${focus ?? ""}` : `rules:${key}:${focus ?? ""}`, type: activity, ...(focus ? { focus } : {}), createdAt: Date.now(), source: "rules" as const, ...draft }, stored: false };
  },
});
