import type { Doc } from "../_generated/dataModel";
import type { MutationCtx } from "../_generated/server";

/** A usage row as the caller knows it: the user id and the time are filled in here. */
export type UsageRowInput = Omit<Doc<"aiUsage">, "_id" | "_creationTime" | "userId" | "at"> & { at?: number };

/** The one place that writes `aiUsage` (ADR-038). Each row carries the user id the call was made for (ADR-039). A number that is undefined is left out. */
export async function insertUsage(ctx: Pick<MutationCtx, "db">, userId: string, rows: UsageRowInput[]): Promise<void> {
  const now = Date.now();
  for (const r of rows) {
    const clean = Object.fromEntries(Object.entries(r).filter(([, v]) => v !== undefined)) as UsageRowInput;
    await ctx.db.insert("aiUsage", { ...clean, at: r.at ?? now, userId });
  }
}
