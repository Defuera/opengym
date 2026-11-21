import type { ActionCtx } from "../_generated/server";
import { internal } from "../_generated/api";
import { ConfigError, createProviderFromEnv, envInfo } from "../model/ai/factory";
import type { AiProvider } from "../model/ai/provider";
import { type JobDef, type JobResult, type JobTrace, type RunOptions, consoleLogger, runJob } from "../model/ai/runJob";

type Ctx = Pick<ActionCtx, "runQuery">;

/** Provider from the deployment env (AI_PROVIDER, OPENAI_API_KEY, ...). null = AI off, fallbacks only. `model` overrides the env model. */
export function providerFromEnv(model?: string | null): AiProvider | null {
  try {
    return createProviderFromEnv(process.env, undefined, model);
  } catch (e) {
    if (e instanceof ConfigError) {
      consoleLogger.error(`[ai] ${e.message} Using code fallbacks.`);
      return null;
    }
    throw e;
  }
}

/** The provider with the model the owner chose in Settings (queries/settings:override), else the env model. */
export async function providerFor(ctx: Ctx): Promise<AiProvider | null> {
  return providerFromEnv(await ctx.runQuery(internal.queries.settings.override, {}));
}

/**
 * Runs one AI job: prompt, provider, JSON, zod validation, one retry, code fallback. Logs `[ai] job=... path=... ms=...`.
 * Each run that reached the provider is stored (ADR-027): the exact prompt, every attempt, the outcome. A failed store never fails the job.
 */
export async function runAiJob<I, O>(ctx: Ctx & Pick<ActionCtx, "runMutation">, job: JobDef<I, O>, input: I, opts?: RunOptions): Promise<JobResult<O>> {
  const model = await ctx.runQuery(internal.queries.settings.override, {});
  let trace: JobTrace | null = null;
  const r = await runJob(job, input, providerFromEnv(model), consoleLogger, { ...opts, onTrace: (t) => (trace = t) });
  const t = trace as JobTrace | null;
  if (t) {
    const env = envInfo(process.env);
    const usedModel = model?.trim() || env.defaultModel;
    try {
      await ctx.runMutation(internal.jobs.aiCalls.save, { ...t, provider: env.provider, ...(usedModel ? { model: usedModel } : {}) });
    } catch (e) {
      consoleLogger.warn(`[ai] call not stored: ${(e as Error).message}`);
    }
  }
  return r;
}
