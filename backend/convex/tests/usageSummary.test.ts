import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../functions/_generated/api";
import { USAGE_SUMMARY_MAX_ROWS } from "../functions/lib/constants";
import { type PriceMap, costOf, priceKey } from "../functions/model/aiPrices";
import { type UsageRow, summarise } from "../functions/model/usageSummary";
import { TOKEN, setup, type T } from "./helpers";

const DAY = 86_400_000;
const D0 = Date.UTC(2026, 10, 1);
const prices: PriceMap = {
  [priceKey("chat", "m")]: { inputPerMTok: 2, cachedInputPerMTok: 0.5, outputPerMTok: 8 },
  [priceKey("transcribe", "w")]: { perAudioMinute: 0.006 },
  [priceKey("image", "i")]: { perImage: 0.04 },
  [priceKey("chat", "noCache")]: { inputPerMTok: 2, outputPerMTok: 8 },
};
const chat = (o: Partial<UsageRow> = {}): UsageRow => ({ at: D0, userId: "owner", job: "j", kind: "chat", provider: "p", model: "m", ok: true, inputTokens: 1000, outputTokens: 500, ...o });

describe("costOf", () => {
  it("is undefined for an unknown model or an empty map", () => {
    expect(costOf(chat({ model: "zz" }), prices)).toBeUndefined();
    expect(costOf(chat(), {})).toBeUndefined();
  });
  it("prices tokens, with the cached part at its own price", () => {
    expect(costOf(chat(), prices)).toBeCloseTo((1000 * 2 + 500 * 8) / 1e6);
    expect(costOf(chat({ cachedInputTokens: 400, reasoningTokens: 100 }), prices)).toBeCloseTo((600 * 2 + 400 * 0.5 + 500 * 8) / 1e6);
  });
  it("is undefined when a needed price is missing", () => {
    expect(costOf(chat({ model: "noCache", cachedInputTokens: 400 }), prices)).toBeUndefined();
    expect(costOf(chat({ model: "noCache", outputTokens: undefined }), { [priceKey("chat", "noCache")]: { inputPerMTok: 2 } })).toBeCloseTo(0.002);
    expect(costOf(chat({ model: "noCache" }), { [priceKey("chat", "noCache")]: { inputPerMTok: 2 } })).toBeUndefined();
  });
  it("prices audio by the minute and images by the piece, only without tokens", () => {
    const base = { at: 0, userId: "owner", job: "t", provider: "p", ok: true };
    expect(costOf({ ...base, kind: "transcribe", model: "w", audioSeconds: 30 }, prices)).toBeCloseTo(0.003);
    expect(costOf({ ...base, kind: "image", model: "i", images: 2 }, prices)).toBeCloseTo(0.08);
    expect(costOf({ ...base, kind: "image", model: "i", images: 1, inputTokens: 10, outputTokens: 10 }, prices)).toBeUndefined();
  });
  it("is undefined for a good call that reported nothing, 0 for a failed one", () => {
    expect(costOf(chat({ inputTokens: undefined, outputTokens: undefined }), prices)).toBeUndefined();
    expect(costOf(chat({ inputTokens: undefined, outputTokens: undefined, ok: false }), prices)).toBe(0);
  });
});

describe("summarise", () => {
  const rows: UsageRow[] = [
    chat({ at: D0 + 1000 }),
    chat({ at: D0 + 2000, ok: false, reasoningTokens: 50 }),
    chat({ at: D0 + 2 * DAY, job: "k", model: "x", inputTokens: 100, outputTokens: 100 }),
    chat({ at: D0 + 3 * DAY + 5, userId: "u2", job: "j", inputTokens: 300, outputTokens: undefined }),
    { at: D0 + 3 * DAY, userId: "owner", kind: "transcribe", job: "transcribe", provider: "p", model: "w", ok: true, audioSeconds: 60, audioBytes: 5000 },
  ];
  const s = summarise(rows, { from: D0, to: D0 + 4 * DAY, observedTo: D0 + 4 * DAY - 1 }, prices);

  it("totals", () => {
    expect(s.totals).toMatchObject({ calls: 5, failed: 1, inputTokens: 2400, outputTokens: 1100, reasoningTokens: 50, totalTokens: 3500, audioSeconds: 60, audioBytes: 5000, pricedCalls: 4, unpricedCalls: 1 });
    expect(s.totals.costUsd).toBeCloseTo(2 * (1000 * 2 + 500 * 8) / 1e6 + 300 * 2 / 1e6 + 0.006);
  });
  it("per day, per job, per model", () => {
    expect(s.byDay.map((d) => [d.day, d.calls])).toEqual([["2026-11-01", 2], ["2026-11-03", 1], ["2026-11-04", 2]]);
    expect(s.byJob.find((j) => j.job === "j")).toMatchObject({ calls: 3, totalTokens: 3300 });
    expect(s.byModel.find((m) => m.model === "x")).toMatchObject({ calls: 1 });
    expect(s.byModel.find((m) => m.model === "x")!.costUsd).toBeUndefined();
  });
  it("per user, with the 30-day extrapolation over the days since the first call", () => {
    const owner = s.byUser.find((u) => u.userId === "owner")!;
    expect(owner).toMatchObject({ calls: 4, activeDays: 3, windowDays: 4 });
    expect(owner.tokensPerActiveDay).toBeCloseTo(3200 / 3);
    expect(owner.tokensPer30Days).toBeCloseTo((3200 / 4) * 30);
    expect(owner.activeDaysPer30).toBeCloseTo(22.5);
    expect(owner.costUsdPer30Days).toBeCloseTo((owner.costUsd! / 4) * 30);
    const u2 = s.byUser.find((u) => u.userId === "u2")!;
    expect(u2.windowDays).toBe(1);
    expect(u2.tokensPer30Days).toBe(300 * 30);
  });
  it("an empty range is all zeros", () => {
    const e = summarise([], { from: 0, to: 1, observedTo: 1 }, prices);
    expect(e.totals.calls).toBe(0);
    expect(e.totals.costUsd).toBeUndefined();
    expect(e.byUser).toEqual([]);
  });
});

describe("queries/usage:summary", () => {
  let t: T;
  const NOW = Date.UTC(2026, 10, 26, 12);
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(NOW);
    t = setup();
  });
  afterEach(() => vi.useRealTimers());
  const row = (at: number) => ({ at, userId: "owner", job: "j", kind: "chat" as const, provider: "p", model: "m", ms: 1, ok: true, inputTokens: 10, outputTokens: 5 });
  const summary = (a: { from?: number; to?: number } = {}) => t.query(api.queries.usage.summary, { token: TOKEN, ...a });

  it("needs the token", async () => {
    await expect(t.query(api.queries.usage.summary, { token: "bad" })).rejects.toThrow(/unauthorized/);
  });
  it("reads the last 30 days by default and only the range asked for", async () => {
    await t.run(async (c) => {
      await c.db.insert("aiUsage", row(NOW - 40 * DAY));
      await c.db.insert("aiUsage", row(NOW - 2 * DAY));
      await c.db.insert("aiUsage", row(NOW - DAY));
    });
    const s = await summary();
    expect(s).toMatchObject({ rowsRead: 2, truncated: false, totals: { calls: 2, totalTokens: 30 } });
    expect((await summary({ from: NOW - 50 * DAY, to: NOW - 30 * DAY })).totals.calls).toBe(1);
  });
  it("rejects a range that is backwards or too long", async () => {
    await expect(summary({ from: NOW, to: NOW - 1 })).rejects.toThrow(/before/);
    await expect(summary({ from: NOW - 400 * DAY, to: NOW })).rejects.toThrow(/longer/);
  });
  it("cuts a read at the row cap and says so", async () => {
    await t.run(async (c) => {
      for (let i = 0; i < USAGE_SUMMARY_MAX_ROWS + 1; i++) await c.db.insert("aiUsage", row(NOW - 10 * DAY + i));
    });
    const s = await summary();
    expect(s.truncated).toBe(true);
    expect(s.rowsRead).toBe(USAGE_SUMMARY_MAX_ROWS);
    expect(s.observedTo).toBe(NOW - 10 * DAY + USAGE_SUMMARY_MAX_ROWS - 1);
  });
  it("the operator report gives the same numbers without a token", async () => {
    await t.run((c) => c.db.insert("aiUsage", row(NOW - DAY)));
    expect((await t.query(internal.queries.usage.report, {})).totals.calls).toBe(1);
  });
});
