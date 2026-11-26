import { ConvexError, v } from "convex/values";
import { internalQuery, query } from "../_generated/server";
import type { QueryCtx } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { USAGE_SUMMARY_DEFAULT_DAYS, USAGE_SUMMARY_MAX_DAYS, USAGE_SUMMARY_MAX_ROWS } from "../lib/constants";
import { AI_PRICES } from "../model/aiPrices";
import { summarise } from "../model/usageSummary";

const DAY = 86_400_000;
const args = { from: v.optional(v.number()), to: v.optional(v.number()) };

/** Reads `aiUsage` in [from, to) (ms since epoch; `to` defaults to now, `from` to 30 days before `to`) and sums it. See `summarise` for the formulas. */
async function readSummary(ctx: Pick<QueryCtx, "db">, a: { from?: number; to?: number }) {
  const to = a.to ?? Date.now();
  const from = a.from ?? to - USAGE_SUMMARY_DEFAULT_DAYS * DAY;
  if (!(from < to)) throw new ConvexError("from must be before to");
  if (to - from > USAGE_SUMMARY_MAX_DAYS * DAY) throw new ConvexError(`the range is longer than ${USAGE_SUMMARY_MAX_DAYS} days`);
  const rows = await ctx.db.query("aiUsage").withIndex("by_at", (q) => q.gte("at", from).lt("at", to)).take(USAGE_SUMMARY_MAX_ROWS + 1);
  const truncated = rows.length > USAGE_SUMMARY_MAX_ROWS;
  const used = truncated ? rows.slice(0, USAGE_SUMMARY_MAX_ROWS) : rows;
  const observedTo = truncated ? used[used.length - 1]!.at : Math.min(to, Date.now());
  return { ...summarise(used, { from, to, observedTo }, AI_PRICES), rowsRead: used.length, truncated };
}

/**
 * AI usage report for pricing a subscription (ADR-038). Args `{ token, from?, to? }`, times in ms since epoch.
 * Returns `{ from, to, observedTo, rowsRead, truncated, totals, byDay, byJob, byModel, byUser }`.
 * Totals hold: calls, failed attempts, input / cached / output / reasoning / total tokens, audio seconds and bytes, images,
 * and `costUsd` (only for rows whose model has a price in `model/aiPrices.ts`; `unpricedCalls` counts the rest).
 * Per user: `activeDays` (UTC days with a call), `tokensPerActiveDay`, and `tokensPer30Days` = totalTokens / windowDays * 30,
 * where `windowDays` runs from the user's first active day in the range to `observedTo`. Cost figures follow the same formulas.
 * Reads at most 8000 rows, oldest first. When more exist, `truncated` is true and the numbers cover only up to `observedTo`; ask for a shorter range.
 * A range over 366 days, or `from` not before `to`, throws a ConvexError. Days are UTC.
 */
export const summary = query({
  args: { token: v.string(), ...args },
  handler: async (ctx, { token, ...range }) => {
    requireToken(token);
    return readSummary(ctx, range);
  },
});

/** The same report without a token, for the operator: `npm run usage` (runs `convex run queries/usage:report`). Internal functions cannot be called from the app. */
export const report = internalQuery({
  args,
  handler: async (ctx, range) => readSummary(ctx, range),
});
