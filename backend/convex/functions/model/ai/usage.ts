/**
 * What a provider says one paid call used (ADR-038). Every field is optional: a field the provider did not report stays absent, never 0.
 * `inputTokens` counts ALL input tokens, cached ones included (the OpenAI convention); `cachedInputTokens` is the part of it read from the cache.
 * `reasoningTokens` is the part of `outputTokens` spent on hidden reasoning; it is not billed again.
 */
export interface Usage {
  inputTokens?: number;
  cachedInputTokens?: number;
  outputTokens?: number;
  reasoningTokens?: number;
  /** Speech to text: the audio length when the API reports it (whisper-style `usage.seconds`). */
  audioSeconds?: number;
  /** Image generation: how many images the answer held. */
  images?: number;
  /** Image generation: size and quality as sent, e.g. "1536x1024 medium". */
  imageSpec?: string;
  /** Images sent in with the prompt (photos for an edit, pictures for vision). */
  inputImages?: number;
}

/** A hook a caller passes to learn the usage of one call. Called at most once per call, as soon as the answer is read, also when the answer is then rejected. */
export interface UsageHook {
  onUsage?(usage: Usage): void;
}

const num = (v: unknown): number | undefined => (typeof v === "number" && Number.isFinite(v) && v >= 0 ? v : undefined);
const obj = (v: unknown): Record<string, unknown> | undefined => (v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : undefined);

/** Drops the absent fields; returns undefined when nothing is left. */
function compact(u: Usage): Usage | undefined {
  const out = Object.fromEntries(Object.entries(u).filter(([, v]) => v !== undefined)) as Usage;
  return Object.keys(out).length > 0 ? out : undefined;
}

/**
 * The `usage` object of an OpenAI-style answer. Reads both wire formats:
 * chat completions (`prompt_tokens`, `completion_tokens`, `prompt_tokens_details.cached_tokens`, `completion_tokens_details.reasoning_tokens`)
 * and responses style (`input_tokens`, `output_tokens`, `input_tokens_details.cached_tokens`, `output_tokens_details.reasoning_tokens`).
 * DeepSeek reports the cached part as `prompt_cache_hit_tokens`.
 */
export function chatUsage(raw: unknown): Usage | undefined {
  const u = obj(raw);
  if (!u) return undefined;
  return compact({
    inputTokens: num(u.prompt_tokens) ?? num(u.input_tokens),
    cachedInputTokens: num(obj(u.prompt_tokens_details)?.cached_tokens) ?? num(obj(u.input_tokens_details)?.cached_tokens) ?? num(u.prompt_cache_hit_tokens),
    outputTokens: num(u.completion_tokens) ?? num(u.output_tokens),
    reasoningTokens: num(obj(u.completion_tokens_details)?.reasoning_tokens) ?? num(obj(u.output_tokens_details)?.reasoning_tokens),
  });
}

/**
 * The `usage` object of an Anthropic messages answer. There `input_tokens` leaves out the cache: the total input is
 * `input_tokens + cache_read_input_tokens + cache_creation_input_tokens`. Cache writes are folded into `inputTokens` (they cost more; see ADR-038).
 */
export function anthropicUsage(raw: unknown): Usage | undefined {
  const u = obj(raw);
  if (!u) return undefined;
  const parts = [num(u.input_tokens), num(u.cache_read_input_tokens), num(u.cache_creation_input_tokens)];
  const input = parts.some((p) => p !== undefined) ? parts.reduce<number>((n, p) => n + (p ?? 0), 0) : undefined;
  return compact({ inputTokens: input, cachedInputTokens: num(u.cache_read_input_tokens), outputTokens: num(u.output_tokens) });
}

/**
 * The `usage` of a speech-to-text answer: `{ type: "tokens", input_tokens, output_tokens }` (gpt-4o-transcribe) or
 * `{ type: "duration", seconds }` (whisper-1). Reads whichever fields are there.
 */
export function transcribeUsage(data: unknown): Usage | undefined {
  const u = obj(obj(data)?.usage);
  if (!u) return undefined;
  return compact({ inputTokens: num(u.input_tokens), outputTokens: num(u.output_tokens), audioSeconds: num(u.seconds) });
}

/** What an image call used: the count of images in the answer (`data` array), the spec as sent, the photos sent in, and tokens when the answer has `usage`. */
export function imageUsage(data: unknown, sent: { spec: string; inputImages: number }): Usage {
  const d = obj(data);
  return {
    ...chatUsage(d?.usage),
    ...(Array.isArray(d?.data) ? { images: (d!.data as unknown[]).length } : {}),
    imageSpec: sent.spec,
    inputImages: sent.inputImages,
  };
}

/** Calls a usage hook; a hook that throws never fails the paid call. */
export function reportUsage(hook: UsageHook | undefined, usage: Usage | undefined): void {
  if (!hook?.onUsage || !usage) return;
  try {
    hook.onUsage(usage);
  } catch {
    // Counting is never worth a failed call.
  }
}

const SUM_FIELDS = ["inputTokens", "cachedInputTokens", "outputTokens", "reasoningTokens", "audioSeconds", "images", "inputImages"] as const;

/** Adds the numbers of several usages. A field that no usage reported stays absent. Text fields (`imageSpec`) are not summed. */
export function sumUsage(list: (Usage | undefined)[]): Usage {
  const out: Usage = {};
  for (const u of list) {
    if (!u) continue;
    for (const f of SUM_FIELDS) if (u[f] !== undefined) out[f] = (out[f] ?? 0) + u[f]!;
  }
  return out;
}
