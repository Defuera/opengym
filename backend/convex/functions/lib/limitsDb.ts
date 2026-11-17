import type { Doc } from "../_generated/dataModel";
import type { DatabaseReader } from "../_generated/server";
import type { Limit } from "../model/schema";

type Reader = { db: DatabaseReader };

export const limitByLimitId = (ctx: Reader, limitId: string) =>
  ctx.db.query("limits").withIndex("by_limitId", (q) => q.eq("limitId", limitId)).unique();

export const recordByRecordId = (ctx: Reader, recordId: string) =>
  ctx.db.query("records").withIndex("by_recordId", (q) => q.eq("recordId", recordId)).unique();

export const checkinByCheckinId = (ctx: Reader, checkinId: string) =>
  ctx.db.query("checkins").withIndex("by_checkinId", (q) => q.eq("checkinId", checkinId)).unique();

/** A stored limit as the model sees it. No records here, by design (ADR-015). */
export function toLimit(d: Doc<"limits">): Limit {
  return {
    limitId: d.limitId,
    part: d.part as Limit["part"],
    title: d.title,
    status: d.status,
    ...(d.since !== undefined ? { since: d.since } : {}),
    rules: d.rules.map((r) => ({ kind: r.kind, text: r.text, ...(r.exercises !== undefined ? { exercises: r.exercises } : {}) })),
  };
}

/** The limits an AI job and the hard checks work from: every limit that is not cleared. */
export async function activeLimits(ctx: Reader): Promise<Limit[]> {
  const docs = await ctx.db.query("limits").collect();
  return docs.filter((d) => d.status !== "cleared").map(toLimit);
}
