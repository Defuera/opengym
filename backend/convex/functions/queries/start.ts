import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { allSessions, startRequestById, storedPredictions } from "../lib/db";
import { rulesPredictions } from "../model/rules/predictions";

/**
 * What the user will most likely do next, most likely first. Items come from the log (ADR-016): several activities with sets may be in the list ("Gym", "Home", ...), at most 2 items per activity and 6 in total, each with the advised `focus` when there is one. An empty log gives an empty list. Never calls the AI.
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

/**
 * The state of a typed start request, or null when there is none (never made, or removed after a day).
 * `proposal.plan` is the plan shape of queries/plans:next and is present exactly when `proposal.kind` is "gym".
 * The app subscribes to this; the proposal arrives when the interpret_request job has run.
 */
export const request = query({
  args: { token: v.string(), requestId: v.string() },
  handler: async (ctx, { token, requestId }) => {
    requireToken(token);
    const doc = await startRequestById(ctx, requestId);
    if (!doc) return null;
    const p = doc.proposal;
    if (doc.status === "pending" || !p) return { requestId: doc.requestId, status: doc.status };
    const plan =
      p.kind === "gym" && p.plan
        ? { id: `start:${doc.requestId}`, type: p.type, ...(p.focus ? { focus: p.focus } : {}), createdAt: doc.createdAt, source: p.plan.source, rationale: p.plan.rationale, exercises: p.plan.exercises }
        : undefined;
    return {
      requestId: doc.requestId,
      status: doc.status,
      proposal: {
        kind: p.kind,
        type: p.type,
        ...(p.focus ? { focus: p.focus } : {}),
        ...(p.minutes !== undefined ? { minutes: p.minutes } : {}),
        ...(p.reason ? { reason: p.reason } : {}),
        ...(plan ? { plan } : {}),
      },
    };
  },
});
