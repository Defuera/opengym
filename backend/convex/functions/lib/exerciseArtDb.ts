import { internal } from "../_generated/api";
import type { MutationCtx } from "../_generated/server";
import { EXERCISE_ART_DAILY_MAX, EXERCISE_ART_RETRY_MS } from "./constants";
import { ART_NAME_MAX, artKey } from "../model/exerciseArt";

/**
 * Makes sure art is on its way for these exercise names (already trimmed, 1..80 characters). A name with no row gets a `pending` row and a job.
 * A `failed` row older than 24 hours goes back to `pending` and the job runs again. Other rows stay. At most EXERCISE_ART_DAILY_MAX rows
 * are new or retried within 24 hours (counted by updatedAt); names over the cap are skipped silently. Idempotent.
 */
export async function requestExerciseArt(ctx: MutationCtx, names: string[]): Promise<void> {
  const now = Date.now();
  let budget = EXERCISE_ART_DAILY_MAX - (await ctx.db.query("exerciseArt").withIndex("by_updatedAt", (q) => q.gte("updatedAt", now - EXERCISE_ART_RETRY_MS)).collect()).length;
  const seen = new Set<string>();
  for (const raw of names) {
    const name = raw.trim().replace(/\s+/g, " ");
    const key = artKey(name);
    if (!key || key.length > ART_NAME_MAX || seen.has(key)) continue;
    seen.add(key);
    const row = await ctx.db.query("exerciseArt").withIndex("by_key", (q) => q.eq("key", key)).first();
    if (row && !(row.status === "failed" && row.updatedAt < now - EXERCISE_ART_RETRY_MS)) continue;
    if (budget <= 0) continue;
    budget--;
    if (row) await ctx.db.patch(row._id, { status: "pending", error: undefined, updatedAt: now });
    else await ctx.db.insert("exerciseArt", { key, name, status: "pending", createdAt: now, updatedAt: now });
    await ctx.scheduler.runAfter(0, internal.jobs.exerciseArt.make, { key });
  }
}
