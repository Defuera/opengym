import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { allSessions, storedPredictions } from "../lib/db";
import { rulesPredictions } from "../model/rules/predictions";

/**
 * What the user will most likely do next, most likely first. One item per ACTIVITY ("Gym" at most once), each with the advised `focus` when there is one. Never calls the AI.
 * `source` is "ai" or "rules". With no stored row (`stored: false`) it is the rules rotation computed here.
 */
export const predictions = query({
  args: { token: v.string() },
  handler: async (ctx, { token }) => {
    requireToken(token);
    const doc = await storedPredictions(ctx);
    if (doc) return { predictions: doc.items, source: doc.source, stored: true };
    return { predictions: rulesPredictions(await allSessions(ctx), Date.now()), source: "rules" as const, stored: false };
  },
});
