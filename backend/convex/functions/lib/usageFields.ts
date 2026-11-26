import { v } from "convex/values";

/** The numbers one paid AI call used. Each is optional: a number the provider did not report is absent, never 0 (ADR-038). */
export const usageNumbers = {
  inputTokens: v.optional(v.number()),
  cachedInputTokens: v.optional(v.number()),
  outputTokens: v.optional(v.number()),
  reasoningTokens: v.optional(v.number()),
  audioSeconds: v.optional(v.number()),
  audioBytes: v.optional(v.number()),
  images: v.optional(v.number()),
  imageSpec: v.optional(v.string()),
  inputImages: v.optional(v.number()),
};

export const usageKind = v.union(v.literal("chat"), v.literal("transcribe"), v.literal("image"));

/** One row of `aiUsage`: one provider attempt. No prompt text. */
export const aiUsageFields = {
  at: v.number(),
  userId: v.string(),
  job: v.string(),
  kind: usageKind,
  provider: v.string(),
  model: v.string(),
  ...usageNumbers,
  ms: v.number(),
  ok: v.boolean(),
  ref: v.optional(v.string()),
};
