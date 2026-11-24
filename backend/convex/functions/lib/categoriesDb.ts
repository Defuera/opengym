import type { DatabaseReader, MutationCtx } from "../_generated/server";
import { liveEntryDocs } from "./db";
import { categoryKey, categoryLabel, usedCategories } from "../model/entryCategory";
import { fallbackColor, parseColor } from "../model/categoryColor";

type Reader = { db: DatabaseReader };

/** How many recent entries are scanned for the order of use. */
const CATEGORY_SCAN = 200;

export interface KnownCategory {
  label: string;
  /** Absent for a label that has no stored row yet (an old label before `jobs/migrations:categoryColors`). */
  color?: string;
}

/** The colour of each category by key (`categoryKey` of the label). */
export async function categoryColors(ctx: Reader): Promise<Map<string, string>> {
  return new Map((await ctx.db.query("entryCategories").collect()).map((r) => [r.key, r.color]));
}

/**
 * The categories the AI is told about, with their stored colours: the labels of the person's recent entries, most used first, then
 * the stored categories no recent entry uses. Old labels (Meal, Training, ...) count as their new label.
 */
export async function knownCategories(ctx: Reader): Promise<KnownCategory[]> {
  const rows = await ctx.db.query("entryCategories").collect();
  const docs = await liveEntryDocs(ctx, { order: "desc", limit: CATEGORY_SCAN });
  const used = usedCategories(docs.map((d) => (d.read?.status === "ready" ? d.read.kind : undefined)));
  const byKey = new Map(rows.map((r) => [r.key, r]));
  const out: KnownCategory[] = used.map((label) => {
    const r = byKey.get(categoryKey(label));
    return { label: r?.label ?? label, ...(r ? { color: r.color } : {}) };
  });
  const seen = new Set(out.map((c) => categoryKey(c.label)));
  for (const r of rows) if (!seen.has(r.key)) out.push({ label: r.label, color: r.color });
  return out;
}

/**
 * The stored category for a label, made when it is new (the label is tidied already). `color` is the AI's colour: kept when it is a hex
 * colour, else the plain fallback. Once stored, a colour never changes. Null for a label that is no category ("other").
 */
export async function ensureCategory(ctx: MutationCtx, kind: string, color: string | null | undefined, source: "ai" | "rules"): Promise<{ label: string; color: string } | null> {
  const label = categoryLabel(kind);
  if (!label) return null;
  const key = categoryKey(label);
  const old = await ctx.db.query("entryCategories").withIndex("by_key", (q) => q.eq("key", key)).unique();
  if (old) return { label: old.label, color: old.color };
  const rows = await ctx.db.query("entryCategories").collect();
  const chosen = parseColor(color) ?? fallbackColor(rows.map((r) => r.color));
  await ctx.db.insert("entryCategories", { key, label, color: chosen, createdAt: Date.now(), source });
  return { label, color: chosen };
}
