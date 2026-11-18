import type { Doc } from "../_generated/dataModel";
import type { MutationCtx } from "../_generated/server";
import { IMPORT_DELETE_BATCH } from "./constants";
import { markFactsChanged } from "./factsChanged";
import { sessionRowBySessionId } from "./db";

type Fields<T extends "sessions" | "goals" | "context"> = Omit<Doc<T>, "_id" | "_creationTime">;

export interface ImportItems {
  sessions?: Fields<"sessions">[];
  goals?: Fields<"goals">[];
  context?: Fields<"context">[];
}

/**
 * Writes already validated import items. Sessions are upserts by sessionId (same as a normal save). The lookup is the RAW one:
 * a row marked as deleted (ADR-020) is not brought back and not duplicated (two rows with one sessionId would break `.unique()`),
 * so an import item for it is skipped.
 */
export async function writeImportItems(ctx: MutationCtx, items: ImportItems): Promise<number> {
  for (const s of items.sessions ?? []) {
    const old = await sessionRowBySessionId(ctx, s.sessionId);
    if (old?.deletedAt !== undefined) continue;
    if (old) await ctx.db.replace(old._id, s);
    else await ctx.db.insert("sessions", s);
  }
  for (const g of items.goals ?? []) await ctx.db.insert("goals", g);
  for (const c of items.context ?? []) await ctx.db.insert("context", c);
  return (items.sessions?.length ?? 0) + (items.goals?.length ?? 0) + (items.context?.length ?? 0);
}

/**
 * Deletes up to IMPORT_DELETE_BATCH documents tagged with importId (marked rows too: removing an import erases its rows at once). When nothing is left it deletes
 * the job row and signals a rebuild, and returns true. Returns false when another pass is needed.
 */
export async function purgeImportStep(ctx: MutationCtx, importId: string): Promise<boolean> {
  let budget = IMPORT_DELETE_BATCH;
  for (const table of ["sessions", "goals", "context"] as const) {
    if (budget <= 0) break;
    const docs = await ctx.db.query(table).withIndex("by_importId", (q) => q.eq("importId", importId)).take(budget);
    for (const d of docs) await ctx.db.delete(d._id);
    budget -= docs.length;
  }
  if (budget <= 0) return false;
  const job = await ctx.db.query("imports").withIndex("by_importId", (q) => q.eq("importId", importId)).unique();
  if (job) await ctx.db.delete(job._id);
  await markFactsChanged(ctx);
  return true;
}
