import { type CostRow, type PriceMap, costOf } from "./aiPrices";

/** One `aiUsage` row as the summary reads it. */
export interface UsageRow extends CostRow {
  at: number;
  userId: string;
  job: string;
  provider: string;
  audioBytes?: number;
}

export interface Totals {
  calls: number;
  /** Attempts that did not give a valid result (a failed request, or a reply the checks rejected). They may still have cost tokens. */
  failed: number;
  inputTokens: number;
  cachedInputTokens: number;
  outputTokens: number;
  reasoningTokens: number;
  /** inputTokens + outputTokens (reasoning is inside the output). */
  totalTokens: number;
  audioSeconds: number;
  audioBytes: number;
  images: number;
  /** Sum of the cost of the rows whose cost is known; absent when no row has a known cost. */
  costUsd?: number;
  /** Rows whose cost is known / unknown (no price for the model, or nothing reported). */
  pricedCalls: number;
  unpricedCalls: number;
}

export interface UserTotals extends Totals {
  userId: string;
  activeDays: number;
  /** First UTC day with a call in range, and the days from it to the end of the observed range (inclusive). */
  windowDays: number;
  tokensPerActiveDay: number;
  costUsdPerActiveDay?: number;
  /** activeDays / windowDays * 30. */
  activeDaysPer30: number;
  tokensPer30Days: number;
  costUsdPer30Days?: number;
}

const DAY = 86_400_000;
export const dayOf = (at: number): string => new Date(at).toISOString().slice(0, 10);
const dayStart = (at: number): number => Math.floor(at / DAY) * DAY;

function emptyTotals(): Totals {
  return { calls: 0, failed: 0, inputTokens: 0, cachedInputTokens: 0, outputTokens: 0, reasoningTokens: 0, totalTokens: 0, audioSeconds: 0, audioBytes: 0, images: 0, pricedCalls: 0, unpricedCalls: 0 };
}

function add(t: Totals, r: UsageRow, prices: PriceMap): void {
  t.calls++;
  if (!r.ok) t.failed++;
  t.inputTokens += r.inputTokens ?? 0;
  t.cachedInputTokens += r.cachedInputTokens ?? 0;
  t.outputTokens += r.outputTokens ?? 0;
  t.reasoningTokens += r.reasoningTokens ?? 0;
  t.totalTokens += (r.inputTokens ?? 0) + (r.outputTokens ?? 0);
  t.audioSeconds += r.audioSeconds ?? 0;
  t.audioBytes += r.audioBytes ?? 0;
  t.images += r.images ?? 0;
  const c = costOf(r, prices);
  if (c === undefined) t.unpricedCalls++;
  else {
    t.pricedCalls++;
    t.costUsd = (t.costUsd ?? 0) + c;
  }
}

function group<K extends object>(rows: UsageRow[], prices: PriceMap, key: (r: UsageRow) => string, label: (r: UsageRow) => K): (K & Totals)[] {
  const map = new Map<string, K & Totals>();
  for (const r of rows) {
    let g = map.get(key(r));
    if (!g) map.set(key(r), (g = { ...label(r), ...emptyTotals() }));
    add(g, r, prices);
  }
  return [...map.values()];
}

/**
 * The report over rows already read (queries/usage). Pure, so it is tested without a database.
 * - `from` / `to` are the range asked for; `observedTo` is where the numbers stop: `to`, or the last row's time when the read was cut short.
 * - Days are UTC days. An active day is a day on which the user made at least one call.
 * - Per user: `windowDays` = days from the user's first active day in range to the day of `observedTo`, both included (at least 1).
 *   `tokensPerActiveDay` = totalTokens / activeDays. `tokensPer30Days` = totalTokens / windowDays * 30 (the same for cost).
 *   `activeDaysPer30` = activeDays / windowDays * 30. So a user's 30-day figure is the pace over the days since the user started using the app, not over the whole range.
 *   Few days of data make these figures noisy; treat them as a first estimate only.
 */
export function summarise(rows: UsageRow[], range: { from: number; to: number; observedTo: number }, prices: PriceMap) {
  const totals = emptyTotals();
  for (const r of rows) add(totals, r, prices);
  const byDay = group(rows, prices, (r) => dayOf(r.at), (r) => ({ day: dayOf(r.at) })).sort((a, b) => a.day.localeCompare(b.day));
  const byJob = group(rows, prices, (r) => `${r.kind}/${r.job}`, (r) => ({ job: r.job, kind: r.kind })).sort((a, b) => b.totalTokens - a.totalTokens || b.calls - a.calls);
  const byModel = group(rows, prices, (r) => `${r.kind}/${r.provider}/${r.model}`, (r) => ({ provider: r.provider, model: r.model, kind: r.kind })).sort((a, b) => b.totalTokens - a.totalTokens || b.calls - a.calls);
  const byUser: UserTotals[] = group(rows, prices, (r) => r.userId, (r) => ({ userId: r.userId })).map((u) => {
    const mine = rows.filter((r) => r.userId === u.userId);
    const days = new Set(mine.map((r) => dayOf(r.at)));
    const first = Math.min(...mine.map((r) => r.at));
    const windowDays = Math.max(1, Math.floor((dayStart(range.observedTo) - dayStart(first)) / DAY) + 1);
    return {
      ...u,
      activeDays: days.size,
      windowDays,
      tokensPerActiveDay: u.totalTokens / days.size,
      ...(u.costUsd !== undefined ? { costUsdPerActiveDay: u.costUsd / days.size } : {}),
      activeDaysPer30: (days.size / windowDays) * 30,
      tokensPer30Days: (u.totalTokens / windowDays) * 30,
      ...(u.costUsd !== undefined ? { costUsdPer30Days: (u.costUsd / windowDays) * 30 } : {}),
    };
  }).sort((a, b) => b.totalTokens - a.totalTokens);
  return { from: range.from, to: range.to, observedTo: range.observedTo, totals, byDay, byJob, byModel, byUser };
}
