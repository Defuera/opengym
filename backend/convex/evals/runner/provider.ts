import { createProviderFromEnv, envInfo } from "../../functions/model/ai/factory";
import type { AiProvider, CompleteRequest } from "../../functions/model/ai/provider";
import { BUDGET_ERROR, type Budget } from "./budget";
import type { CallRecorder } from "./types";

type Env = Record<string, string | undefined>;

export interface ProviderSetup {
  provider: string;
  model: string;
  /** A fresh provider for one case: its own recorder, counted against the shared budget. */
  make(rec: CallRecorder, budget: Budget): AiProvider;
}

const num = (v: unknown): number | undefined => (typeof v === "number" && Number.isFinite(v) ? v : undefined);

/** Wraps fetch so the token usage of each response lands in the recorder. The body is read from a clone; the adapter sees the response untouched. */
export function usageFetch(rec: CallRecorder, base: typeof fetch): typeof fetch {
  return async (input, init) => {
    const res = await base(input, init);
    try {
      const u = ((await res.clone().json()) as { usage?: Record<string, unknown> }).usage ?? {};
      rec.usage = { promptTokens: num(u.prompt_tokens) ?? num(u.input_tokens), completionTokens: num(u.completion_tokens) ?? num(u.output_tokens) };
    } catch {
      rec.usage = {};
    }
    return res;
  };
}

/** The real adapter, wrapped: counts the budget, times the call, keeps the raw answer and the usage. */
function recording(inner: AiProvider, rec: CallRecorder, budget: Budget): AiProvider {
  return {
    name: inner.name,
    supportsImages: inner.supportsImages,
    listModels: () => inner.listModels(),
    async complete(req: CompleteRequest) {
      if (!budget.take()) {
        rec.calls.push({ ms: 0, error: BUDGET_ERROR });
        throw new Error(BUDGET_ERROR);
      }
      rec.usage = {};
      const t0 = Date.now();
      try {
        const raw = await inner.complete(req);
        rec.calls.push({ ms: Date.now() - t0, raw, ...rec.usage });
        return raw;
      } catch (e) {
        rec.calls.push({ ms: Date.now() - t0, error: (e as Error).message, ...rec.usage });
        throw e;
      }
    },
  };
}

/**
 * Provider and model from the same env names the server uses (AI_PROVIDER, OPENAI_API_KEY, OPENAI_MODEL, ...).
 * EVAL_PROVIDER replaces AI_PROVIDER; EVAL_MODEL replaces the model (as the owner's choice in Settings does). Never reads a file.
 */
export function setupProvider(env: Env, baseFetch: typeof fetch = fetch): ProviderSetup {
  const merged: Env = { ...env, AI_PROVIDER: env.EVAL_PROVIDER?.trim() || env.AI_PROVIDER };
  const override = env.EVAL_MODEL?.trim() || null;
  const info = envInfo(merged);
  if (info.provider === "none") throw new Error("No provider: set AI_PROVIDER (or EVAL_PROVIDER) to anthropic, openai, deepseek or mock.");
  createProviderFromEnv(merged, undefined, override); // fails early on a missing key or model
  return {
    provider: info.provider,
    model: override ?? info.defaultModel ?? info.provider,
    make: (rec, budget) => recording(createProviderFromEnv(merged, usageFetch(rec, baseFetch), override)!, rec, budget),
  };
}
