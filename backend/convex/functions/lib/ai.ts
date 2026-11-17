import type { ActionCtx } from "../_generated/server";
import { internal } from "../_generated/api";
import { ConfigError, createProviderFromEnv } from "../model/ai/factory";
import type { AiProvider } from "../model/ai/provider";
import { type JobDef, type JobResult, type RunOptions, consoleLogger, runJob } from "../model/ai/runJob";

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

/** Runs one AI job: prompt, provider, JSON, zod validation, one retry, code fallback. Logs `[ai] job=... path=... ms=...`. */
export async function runAiJob<I, O>(ctx: Ctx, job: JobDef<I, O>, input: I, opts?: RunOptions): Promise<JobResult<O>> {
  return runJob(job, input, await providerFor(ctx), consoleLogger, opts);
}
