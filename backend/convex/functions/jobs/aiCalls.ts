import { v } from "convex/values";
import { internalMutation } from "../_generated/server";
import { AI_CALL_TEXT_MAX } from "../lib/constants";

const cut = (s: string): string => (s.length > AI_CALL_TEXT_MAX ? s.slice(0, AI_CALL_TEXT_MAX) : s);

/** Stores one AI job run (ADR-027). Called by lib/ai.ts after every job; long texts are cut so a row stays under the document limit. */
export const save = internalMutation({
  args: {
    job: v.string(),
    provider: v.string(),
    model: v.optional(v.string()),
    system: v.string(),
    messages: v.array(v.object({ role: v.union(v.literal("user"), v.literal("assistant")), content: v.string() })),
    images: v.number(),
    attempts: v.array(v.object({ raw: v.optional(v.string()), error: v.optional(v.string()), ms: v.number() })),
    path: v.union(v.literal("ai"), v.literal("fallback")),
    reason: v.optional(v.string()),
    ms: v.number(),
  },
  handler: async (ctx, a): Promise<void> => {
    await ctx.db.insert("aiCalls", {
      ...a,
      at: Date.now(),
      system: cut(a.system),
      messages: a.messages.map((m) => ({ role: m.role, content: cut(m.content) })),
      attempts: a.attempts.map((t) => ({ ms: t.ms, ...(t.raw !== undefined ? { raw: cut(t.raw) } : {}), ...(t.error !== undefined ? { error: t.error.slice(0, 2000) } : {}) })),
      ...(a.reason !== undefined ? { reason: a.reason.slice(0, 2000) } : {}),
    });
  },
});
