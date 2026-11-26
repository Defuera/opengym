import type { Usage } from "./ai/usage";

/** What one paid call is billed at, in US dollars. Every field is optional: a price you do not know stays absent (ADR-038). */
export interface ModelPrice {
  /** Per 1,000,000 input tokens (cached ones included in the count; see `cachedInputPerMTok`). */
  inputPerMTok?: number;
  /** Per 1,000,000 cached input tokens. When a call reports cached tokens, this price is required to price it. */
  cachedInputPerMTok?: number;
  /** Per 1,000,000 output tokens. Reasoning tokens are part of the output tokens and are not billed a second time. */
  outputPerMTok?: number;
  /** Speech to text billed by audio length (whisper-style). Used only when the call reported no tokens. */
  perAudioMinute?: number;
  /** Image billed per picture. Used only when the call reported no tokens. */
  perImage?: number;
}

export type PriceMap = Record<string, ModelPrice>;
export type UsageKind = "chat" | "transcribe" | "image";

/** The key of a model in a price map: kind and model id, e.g. "chat:gpt-5.1" or "image:gpt-image-2". */
export const priceKey = (kind: UsageKind, model: string): string => `${kind}:${model}`;

/**
 * The prices of the models the app uses. EMPTY ON PURPOSE: no price is in this repo, and a made-up price would make every cost number wrong.
 *
 * To fill it, read the current price page of the provider for each model you use, and add one entry per model and kind, for example:
 *   [priceKey("chat", "<model id from OPENAI_MODEL>")]: { inputPerMTok: <usd>, cachedInputPerMTok: <usd>, outputPerMTok: <usd> },
 *   [priceKey("transcribe", "gpt-4o-transcribe")]: { inputPerMTok: <usd>, outputPerMTok: <usd> },
 *   [priceKey("image", "gpt-image-2")]: { inputPerMTok: <usd>, outputPerMTok: <usd> },
 * Use the model id exactly as the `model` column of `aiUsage` shows it. Note the date you read the price in a comment next to the entry.
 * Until a model has an entry, its cost is unknown and the report says so (`unpricedCalls`).
 */
export const AI_PRICES: PriceMap = {};

/** The part of a usage row that costs money. */
export type CostRow = Usage & { kind: UsageKind; model: string; ok: boolean };

const M = 1_000_000;

/**
 * The cost in USD of one `aiUsage` row, or `undefined` when it cannot be known:
 * - the model has no entry in `prices`;
 * - the row used something (tokens, cached tokens, audio, images) whose price is missing;
 * - the call succeeded but the provider reported nothing to bill.
 * Rules (inferred from how the providers bill; check them against the price page when you fill the map):
 * - `inputTokens` include the cached ones: uncached = input - cached, billed at `inputPerMTok`; cached at `cachedInputPerMTok`.
 * - Reasoning tokens are inside `outputTokens`; they add nothing.
 * - Audio seconds and image count are billed per minute / per image only when the row has no token numbers (token billing wins).
 * - A failed call that reported nothing costs 0 (inferred: an error answer is not billed; a timeout may still be, which this cannot see).
 */
export function costOf(row: CostRow, prices: PriceMap): number | undefined {
  const p = prices[priceKey(row.kind, row.model)];
  if (!p) return undefined;
  const hasTokens = row.inputTokens !== undefined || row.outputTokens !== undefined || row.cachedInputTokens !== undefined;
  let usd = 0;
  let billed = false;
  if (hasTokens) {
    const input = row.inputTokens ?? 0;
    const cached = Math.min(row.cachedInputTokens ?? 0, input);
    if (input - cached > 0) {
      if (p.inputPerMTok === undefined) return undefined;
      usd += ((input - cached) * p.inputPerMTok) / M;
    }
    if (cached > 0) {
      if (p.cachedInputPerMTok === undefined) return undefined;
      usd += (cached * p.cachedInputPerMTok) / M;
    }
    if (row.outputTokens !== undefined) {
      if (p.outputPerMTok === undefined) return undefined;
      usd += (row.outputTokens * p.outputPerMTok) / M;
    }
    billed = true;
  } else {
    if (row.audioSeconds !== undefined) {
      if (p.perAudioMinute === undefined) return undefined;
      usd += (row.audioSeconds / 60) * p.perAudioMinute;
      billed = true;
    }
    if (row.images !== undefined) {
      if (p.perImage === undefined) return undefined;
      usd += row.images * p.perImage;
      billed = true;
    }
  }
  if (!billed) return row.ok ? undefined : 0;
  return usd;
}
