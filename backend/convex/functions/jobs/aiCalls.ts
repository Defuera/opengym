import { v } from "convex/values";
import { internalMutation } from "../_generated/server";
import { insertUsage } from "../lib/aiUsageDb";
import { AI_CALL_TEXT_MAX } from "../lib/constants";
import { usageNumbers } from "../lib/usageFields";
import { sumUsage } from "../model/ai/usage";

const cut = (s: string): string => (s.length > AI_CALL_TEXT_MAX ? s.slice(0, AI_CALL_TEXT_MAX) : s);

/**
 * Stores one AI job run (ADR-027). Called by lib/ai.ts after every job; long texts are cut so a row stays under the document limit.
 * Also writes one small `aiUsage` row per attempt (ADR-038) and puts the summed tokens on the `aiCalls` row.
 */
export const save = internalMutation({
  args: {
    job: v.string(),
    provider: v.string(),
    model: v.optional(v.string()),
    system: v.string(),
    messages: v.array(v.object({ role: v.union(v.literal("user"), v.literal("assistant")), content: v.string() })),
    images: v.number(),
    attempts: v.array(v.object({ raw: v.optional(v.string()), error: v.optional(v.string()), ms: v.number(), at: v.optional(v.number()), usage: v.optional(v.object(usageNumbers)) })),
    path: v.union(v.literal("ai"), v.literal("fallback")),
    reason: v.optional(v.string()),
    ms: v.number(),
    ref: v.optional(v.string()),
  },
  handler: async (ctx, a): Promise<void> => {
    const sum = sumUsage(a.attempts.map((t) => t.usage));
    const { attempts: _attempts, ...rest } = a;
    await ctx.db.insert("aiCalls", {
      ...rest,
      ...(sum.inputTokens !== undefined ? { inputTokens: sum.inputTokens } : {}),
      ...(sum.cachedInputTokens !== undefined ? { cachedInputTokens: sum.cachedInputTokens } : {}),
      ...(sum.outputTokens !== undefined ? { outputTokens: sum.outputTokens } : {}),
      ...(sum.reasoningTokens !== undefined ? { reasoningTokens: sum.reasoningTokens } : {}),
      at: Date.now(),
      system: cut(a.system),
      messages: a.messages.map((m) => ({ role: m.role, content: cut(m.content) })),
      attempts: a.attempts.map((t) => ({ ms: t.ms, ...(t.raw !== undefined ? { raw: cut(t.raw) } : {}), ...(t.error !== undefined ? { error: t.error.slice(0, 2000) } : {}) })),
      ...(a.reason !== undefined ? { reason: a.reason.slice(0, 2000) } : {}),
    });
    await insertUsage(ctx, a.attempts.map((t) => ({
      ...(t.at !== undefined ? { at: t.at } : {}),
      job: a.job,
      kind: "chat" as const,
      provider: a.provider,
      model: a.model ?? "unknown",
      ...t.usage,
      ms: t.ms,
      ok: t.error === undefined,
      ...(a.ref !== undefined ? { ref: a.ref } : {}),
    })));
  },
});
