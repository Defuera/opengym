import { v } from "convex/values";
import { z } from "zod";
import { internal } from "../_generated/api";
import { mutation } from "../_generated/server";
import { requireUser } from "../lib/auth";
import { patchSettings, settingsRow } from "../lib/settingsDb";
import { parseOrThrow } from "../lib/validate";

/** 1..100 characters: letters, digits and . _ : - only. */
export const ModelIdSchema = z.string().min(1).max(100).regex(/^[A-Za-z0-9._:-]+$/, "use letters, digits and . _ : - only");

/** Set the coach model, or null to go back to the model from the environment. Idempotent. The id need not be in the cached list. */
export const setAiModel = mutation({
  args: { token: v.string(), model: v.union(v.string(), v.null()) },
  handler: async (ctx, { token, model }) => {
    const userId = await requireUser(ctx, token);
    const next = model === null ? undefined : parseOrThrow(ModelIdSchema, model, "model");
    if ((await settingsRow(ctx, userId))?.aiModel === next) return;
    await patchSettings(ctx, userId, { aiModel: next });
  },
});

/** Ask the current provider for its model list (runs in the background). The app sees the result through queries/settings:ai. */
export const refreshModels = mutation({
  args: { token: v.string() },
  handler: async (ctx, { token }) => {
    const userId = await requireUser(ctx, token);
    await ctx.scheduler.runAfter(0, internal.jobs.models.refresh, { userId });
  },
});
