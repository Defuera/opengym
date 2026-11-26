import { v } from "convex/values";
import { mutation } from "../_generated/server";
import { requireUser } from "../lib/auth";
import { stableJson, withoutSystemFields } from "../lib/db";
import { parseOrThrow } from "../lib/validate";
import { trackerDayFields, trackerWorkoutFields } from "../lib/trackerFields";
import { TrackerSyncSchema } from "../model/schema";

/**
 * Upsert a batch of tracker readings (ADR-036): days by `date`, workouts by `workoutId`. Idempotent: the same batch twice changes
 * nothing, and a row that is unchanged is not written. A day replaces the stored row of that date. These are readings from the
 * phone, never sessions; no AI job calls this. Caps: 31 days and 100 workouts a call; field ranges in model/schema/tracker.ts.
 */
export const sync = mutation({
  args: { token: v.string(), days: v.array(v.object(trackerDayFields)), workouts: v.array(v.object(trackerWorkoutFields)) },
  handler: async (ctx, { token, days, workouts }) => {
    const userId = await requireUser(ctx, token);
    const batch = parseOrThrow(TrackerSyncSchema, { days, workouts }, "tracker");
    const now = Date.now();
    let written = 0;
    // A date or id that appears twice in one batch: the last one wins.
    for (const day of [...new Map(batch.days.map((d) => [d.date, d])).values()]) {
      const old = await ctx.db.query("trackerDays").withIndex("by_date", (q) => q.eq("date", day.date)).unique();
      if (old && stableJson(withoutSystemFields({ ...old, updatedAt: 0 })) === stableJson({ ...day, updatedAt: 0, userId })) continue;
      if (old) await ctx.db.replace(old._id, { ...day, updatedAt: now, userId });
      else await ctx.db.insert("trackerDays", { ...day, updatedAt: now, userId });
      written++;
    }
    for (const w of [...new Map(batch.workouts.map((x) => [x.workoutId, x])).values()]) {
      const old = await ctx.db.query("trackerWorkouts").withIndex("by_workoutId", (q) => q.eq("workoutId", w.workoutId)).unique();
      if (old && stableJson(withoutSystemFields({ ...old, updatedAt: 0 })) === stableJson({ ...w, updatedAt: 0, userId })) continue;
      if (old) await ctx.db.replace(old._id, { ...w, updatedAt: now, userId });
      else await ctx.db.insert("trackerWorkouts", { ...w, updatedAt: now, userId });
      written++;
    }
    return { days: batch.days.length, workouts: batch.workouts.length, written };
  },
});
