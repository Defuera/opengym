import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalMutation } from "../_generated/server";
import { markFactsChanged } from "../lib/factsChanged";
import { isLegacyGym, normalizePredictions, normalizeSession } from "../model/sessionShape";

/** Sessions per call. A session holds its sets, so keep this well below the 16k-document limit of one mutation. */
const BATCH = 100;

/**
 * ADR-013, activity first. Run by hand once, after the schema change is deployed:
 *   internal.jobs.migrations.activityFirst   args: {}   (optional: { batch?: number })
 *
 * Phase 1 pages through `sessions`. Every gym session whose type is not "Gym" gets focus = old type
 * (an existing focus is kept) and type = "Gym". Activity sessions are not touched.
 * It schedules itself for the next page until the last one, then does phase 2 in the same call.
 *
 * Phase 2 fixes the stored read models that would break the new shape:
 * - plans: a row with the legacy `type` key gets `focus = type` and the `type` key removed.
 *   If a row for that focus already exists (a rebuild ran between the deploy and this migration),
 *   the older legacy row is a duplicate and is deleted. Nothing else is deleted.
 * - predictions: the single row's items are normalised (gym item -> type "Gym" + focus, Gym once).
 * - reviews and dashboards hold no gym type (a review has free text, a dashboard has layout specs), so they stay.
 * If anything changed it marks facts changed, so the debounced rebuild refreshes the read models.
 *
 * Idempotent: a second run finds nothing to change, writes nothing and does not trigger a rebuild.
 * Returns what this call changed. `done` is false while more pages are scheduled.
 */
export const activityFirst = internalMutation({
  args: { cursor: v.optional(v.union(v.string(), v.null())), batch: v.optional(v.number()) },
  handler: async (ctx, { cursor, batch }) => {
    const page = await ctx.db.query("sessions").paginate({ cursor: cursor ?? null, numItems: Math.max(1, Math.floor(batch ?? BATCH)) });
    let sessions = 0;
    for (const d of page.page) {
      if (!isLegacyGym(d)) continue;
      const n = normalizeSession(d);
      await ctx.db.patch(d._id, { type: n.type, ...(n.focus !== undefined ? { focus: n.focus } : {}) });
      sessions++;
    }
    if (!page.isDone) {
      // Carry the count of this page into the rebuild decision: a later page may find nothing, so mark now.
      if (sessions > 0) await markFactsChanged(ctx);
      await ctx.scheduler.runAfter(0, internal.jobs.migrations.activityFirst, { cursor: page.continueCursor, batch });
      return { sessions, plans: 0, predictions: 0, done: false };
    }

    let plans = 0;
    for (const p of await ctx.db.query("plans").collect()) {
      if (p.focus !== undefined || p.type === undefined) continue;
      const legacy = p.type;
      const existing = await ctx.db.query("plans").withIndex("by_focus", (q) => q.eq("focus", legacy)).first();
      if (existing) await ctx.db.delete(p._id);
      else await ctx.db.patch(p._id, { focus: legacy, type: undefined });
      plans++;
    }
    let predictions = 0;
    const pred = await ctx.db.query("predictions").first();
    if (pred) {
      const items = normalizePredictions(pred.items);
      if (JSON.stringify(items) !== JSON.stringify(pred.items)) {
        await ctx.db.patch(pred._id, { items });
        predictions = 1;
      }
    }
    if (sessions + plans + predictions > 0) await markFactsChanged(ctx);
    return { sessions, plans, predictions, done: true };
  },
});
