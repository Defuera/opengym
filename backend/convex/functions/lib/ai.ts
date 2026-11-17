import { ConfigError, createProviderFromEnv } from "../model/ai/factory";
import type { AiProvider } from "../model/ai/provider";
import { type JobDef, type JobResult, type RunOptions, consoleLogger, runJob } from "../model/ai/runJob";

/** Provider from the deployment env (AI_PROVIDER, OPENAI_API_KEY, ...). null = AI off, fallbacks only. */
export function providerFromEnv(): AiProvider | null {
  try {
    return createProviderFromEnv(process.env);
  } catch (e) {
    if (e instanceof ConfigError) {
      consoleLogger.error(`[ai] ${e.message} Using code fallbacks.`);
      return null;
    }
    throw e;
  }
}

/** Runs one AI job: prompt, provider, JSON, zod validation, one retry, code fallback. Logs `[ai] job=... path=... ms=...`. */
export function runAiJob<I, O>(job: JobDef<I, O>, input: I, opts?: RunOptions): Promise<JobResult<O>> {
  return runJob(job, input, providerFromEnv(), consoleLogger, opts);
}
