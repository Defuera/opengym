import type { AiProvider } from "./provider";
import { AnthropicProvider } from "./providers/anthropic";
import { createDeepSeekProvider } from "./providers/deepseek";
import { MockProvider } from "./providers/mock";
import { createOpenAiProvider } from "./providers/openai";

export class ConfigError extends Error {}

export const PROVIDER_NAMES = ["anthropic", "openai", "deepseek", "mock", "none"] as const;

type Env = Record<string, string | undefined>;

const KEYS: Record<string, { key: string; model: string; base: string }> = {
  anthropic: { key: "ANTHROPIC_API_KEY", model: "ANTHROPIC_MODEL", base: "ANTHROPIC_BASE_URL" },
  openai: { key: "OPENAI_API_KEY", model: "OPENAI_MODEL", base: "OPENAI_BASE_URL" },
  deepseek: { key: "DEEPSEEK_API_KEY", model: "DEEPSEEK_MODEL", base: "DEEPSEEK_BASE_URL" },
};

/** Returns null for AI_PROVIDER unset/none (AI off, fallbacks only). Throws ConfigError when key or model is missing. */
export function createProviderFromEnv(env: Env, fetchImpl?: typeof fetch): AiProvider | null {
  const name = (env.AI_PROVIDER ?? "none").trim().toLowerCase();
  if (name === "none" || name === "") return null;
  if (name === "mock") return new MockProvider();
  const keys = KEYS[name];
  if (!keys) throw new ConfigError(`AI_PROVIDER="${name}" is not one of: ${PROVIDER_NAMES.join(", ")}`);
  const apiKey = env[keys.key]?.trim();
  const model = env[keys.model]?.trim();
  const missing = [!apiKey && keys.key, !model && keys.model].filter(Boolean);
  if (missing.length) throw new ConfigError(`AI_PROVIDER=${name} needs ${missing.join(" and ")} in .env (set the model to a current model id from the provider's docs).`);
  const opts = { apiKey: apiKey!, model: model!, baseUrl: env[keys.base]?.trim() || undefined, fetch: fetchImpl };
  if (name === "anthropic") return new AnthropicProvider(opts);
  if (name === "openai") return createOpenAiProvider(opts);
  return createDeepSeekProvider(opts);
}
