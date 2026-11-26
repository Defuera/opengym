import type { Doc } from "../_generated/dataModel";
import type { DatabaseReader } from "../_generated/server";
import type { Limit } from "../model/schema";
import { type LimitForAi, RECORDS_PER_LIMIT_MAX } from "../model/schema/limits";

type Reader = { db: DatabaseReader };

export const limitByLimitId = (ctx: Reader, userId: string, limitId: string) =>
  ctx.db.query("limits").withIndex("by_limitId", (q) => q.eq("limitId", limitId)).unique();

export const recordByRecordId = (ctx: Reader, userId: string, recordId: string) =>
  ctx.db.query("records").withIndex("by_recordId", (q) => q.eq("recordId", recordId)).unique();

export const checkinByCheckinId = (ctx: Reader, userId: string, checkinId: string) =>
  ctx.db.query("checkins").withIndex("by_checkinId", (q) => q.eq("checkinId", checkinId)).unique();

/** A stored limit without its records. Records are added by `limitsForAi` (ADR-033). */
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
export async function activeLimits(ctx: Reader, userId: string): Promise<Limit[]> {
  const docs = await ctx.db.query("limits").collect();
  return docs.filter((d) => d.status !== "cleared").map(toLimit);
}

/**
 * Every limit, cleared ones too, each with its newest records (date, then written, newest first), for the jobs that read the
 * person's records (ADR-033). Hard checks still use only the non-cleared rules: they skip a cleared limit by its status.
 */
export async function limitsForAi(ctx: Reader, userId: string): Promise<LimitForAi[]> {
  const out: LimitForAi[] = [];
  for (const d of await ctx.db.query("limits").collect()) {
    const rows = (await ctx.db.query("records").withIndex("by_limitId", (q) => q.eq("limitId", d.limitId)).collect())
      .sort((a, b) => (b.date ?? "").localeCompare(a.date ?? "") || b._creationTime - a._creationTime)
      .slice(0, RECORDS_PER_LIMIT_MAX);
    out.push({ ...toLimit(d), ...(rows.length > 0 ? { records: rows.map((r) => ({ title: r.title, ...(r.date !== undefined ? { date: r.date } : {}), text: r.text })) } : {}) });
  }
  return out;
}
