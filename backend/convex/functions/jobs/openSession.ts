import { v } from "convex/values";
import { internalMutation } from "../_generated/server";
import { rebuiltPlan } from "../model/openSession";

const plannedExercise = v.object({
  name: v.string(),
  measure: v.optional(v.literal("time")),
  note: v.optional(v.string()),
  sets: v.array(v.object({ reps: v.optional(v.number()), kg: v.optional(v.number()), max: v.optional(v.boolean()), minutes: v.optional(v.number()), distanceKm: v.optional(v.number()) })),
});

/**
 * An outside writer (the coach, or the owner's tool) gives the open session a new plan (ADR-028). An exercise with a done set stays
 * as it is (model/openSession.ts: mergePlan); the rest is replaced. Changes nothing when there is no open session, or when `id` is
 * given and another session is open. Returns the new `rev`, or null when nothing changed.
 */
export const replacePlan = internalMutation({
  args: { userId: v.string(), id: v.optional(v.string()), by: v.union(v.literal("coach"), v.literal("owner")), exercises: v.array(plannedExercise), focus: v.optional(v.string()), planNote: v.optional(v.string()) },
  handler: async (ctx, { userId, id, by, exercises, focus, planNote }): Promise<number | null> => {
    const row = await ctx.db.query("openSession").first();
    if (!row || (id !== undefined && row.id !== id)) return null;
    let n = 0;
    const stamp = Date.now().toString(36);
    const rev = row.rev + 1;
    await ctx.db.patch(row._id, {
      ...rebuiltPlan(row.exercises, exercises, () => `${stamp}s${(n++).toString(36)}`, focus, planNote),
      rev,
      updatedAt: Date.now(),
      updatedBy: by,
    });
    return rev;
  },
});
