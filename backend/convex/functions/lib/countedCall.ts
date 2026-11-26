import type { ActionCtx } from "../_generated/server";
import { internal } from "../_generated/api";
import type { Usage } from "../model/ai/usage";
import { consoleLogger } from "../model/ai/runJob";

export interface CountedMeta {
  /** The AI job name, or "transcribe" / "exercise_art". */
  job: string;
  kind: "transcribe" | "image";
  provider: string;
  model: string;
  /** Same meaning as `aiCalls.ref`, where the call has one. */
  ref?: string;
  /** Size of the audio sent, when known. */
  audioBytes?: number;
}

/**
 * Runs one paid call that is not an AI job (speech to text, image) and records it in `aiUsage` (ADR-038): one row per call, also a failed one.
 * `call` receives the hook to hand to the provider. The error of a failed call is thrown again after the row is written.
 * A failed write is logged and never changes the result.
 */
export async function countedCall<T>(ctx: Pick<ActionCtx, "runMutation">, meta: CountedMeta, call: (onUsage: (u: Usage) => void) => Promise<T>): Promise<T> {
  const started = Date.now();
  let usage: Usage | undefined;
  let ok = false;
  try {
    const out = await call((u) => (usage = u));
    ok = true;
    return out;
  } finally {
    try {
      await ctx.runMutation(internal.jobs.aiUsage.record, { ...meta, ...usage, ms: Date.now() - started, ok });
    } catch (e) {
      consoleLogger.warn(`[ai] usage not stored: ${(e as Error).message}`);
    }
  }
}
