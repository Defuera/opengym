import { v } from "convex/values";
import { internalMutation } from "../_generated/server";
import { insertUsage } from "../lib/aiUsageDb";
import { usageKind, usageNumbers } from "../lib/usageFields";

/** Records one paid call that is not an AI job run: a speech-to-text or an image call (ADR-038). Called by lib/countedCall.ts. */
export const record = internalMutation({
  args: {
    userId: v.string(),
    job: v.string(),
    kind: usageKind,
    provider: v.string(),
    model: v.string(),
    ...usageNumbers,
    ms: v.number(),
    ok: v.boolean(),
    ref: v.optional(v.string()),
  },
  handler: async (ctx, { userId, ...a }): Promise<void> => {
    await insertUsage(ctx, userId, [a]);
  },
});
