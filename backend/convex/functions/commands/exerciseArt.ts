import { ConvexError, v } from "convex/values";
import { mutation } from "../_generated/server";
import { requireUser } from "../lib/auth";
import { requestExerciseArt } from "../lib/exerciseArtDb";
import { ART_NAME_MAX } from "../model/exerciseArt";

/**
 * Asks for the art of exercises: 1..12 names, each 1..80 after trim. For a name with no art row it starts the job;
 * a failed row older than 24 hours is tried again; other rows stay. At most 40 new or retried rows per 24 hours; names over the cap are skipped silently.
 * Idempotent. Returns null.
 */
export const request = mutation({
  args: { token: v.string(), names: v.array(v.string()) },
  handler: async (ctx, { token, names }): Promise<null> => {
    const userId = await requireUser(ctx, token);
    if (names.length < 1 || names.length > 12) throw new ConvexError("names: must be 1 to 12 names");
    const clean = names.map((n) => n.trim());
    if (clean.some((n) => n.length < 1 || n.length > ART_NAME_MAX)) throw new ConvexError(`names: each name must be 1 to ${ART_NAME_MAX} characters`);
    await requestExerciseArt(ctx, userId, clean);
    return null;
  },
});
