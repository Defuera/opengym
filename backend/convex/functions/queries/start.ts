import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireUser } from "../lib/auth";
import { startRequestById } from "../lib/db";

/**
 * The state of a typed start request, or null when there is none (never made, or removed after a day).
 * `proposal.plan` is the plan shape of queries/plans:next and is present exactly when `proposal.kind` is "gym".
 * The app subscribes to this; the proposal arrives when the interpret_request job has run.
 */
export const request = query({
  args: { token: v.string(), requestId: v.string() },
  handler: async (ctx, { token, requestId }) => {
    const userId = await requireUser(ctx, token);
    const doc = await startRequestById(ctx, userId, requestId);
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
        ...(p.place ? { place: p.place } : {}),
      },
    };
  },
});
