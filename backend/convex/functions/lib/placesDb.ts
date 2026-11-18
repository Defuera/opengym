import type { DatabaseReader, DatabaseWriter } from "../_generated/server";
import type { Doc } from "../_generated/dataModel";
import { PLACE_NAME_MAX, PLACE_QUOTE_MAX, PLACE_TEXT_MAX, placeKey } from "./placeFields";

type Source = "feedback" | "note" | "chat" | "user" | "seed";

/** Every place. There are few (a gym, a home, a hotel), so one read is fine. Sorted by name. */
export async function allPlaces(ctx: { db: DatabaseReader }): Promise<Doc<"places">[]> {
  const rows = await ctx.db.query("places").collect();
  return rows.sort((a, b) => a.name.localeCompare(b.name));
}

export const placeByPlaceId = (ctx: { db: DatabaseReader }, placeId: string) =>
  ctx.db.query("places").withIndex("by_placeId", (q) => q.eq("placeId", placeId)).unique();

/** The place whose name has this key, or null. The name key is unique, so there is at most one. */
export async function placeByName(ctx: { db: DatabaseReader }, name: string): Promise<Doc<"places"> | null> {
  const k = placeKey(name);
  return (await ctx.db.query("places").collect()).find((p) => placeKey(p.name) === k) ?? null;
}

/** Appends one trace row for a change of a place text. The quote is the user's sentence, cut to the limit. */
export function logPlaceChange(ctx: { db: DatabaseWriter }, o: { placeId: string; source: Source; quote: string; before: string; after: string }) {
  return ctx.db.insert("placeChanges", { placeId: o.placeId, at: Date.now(), source: o.source, quote: o.quote.slice(0, PLACE_QUOTE_MAX), before: o.before, after: o.after });
}

/**
 * Sets the text of a place when it differs (cut to the limit) and logs the change. Returns true when it wrote.
 * `expectedBefore`: write only while the stored text is still that (a background job read it earlier; a newer edit wins).
 */
export async function setPlaceText(ctx: { db: DatabaseWriter }, place: Doc<"places">, text: string, source: Source, quote: string, expectedBefore?: string): Promise<boolean> {
  const after = text.trim().slice(0, PLACE_TEXT_MAX);
  if (expectedBefore !== undefined && place.text !== expectedBefore) return false;
  if (after === place.text) return false;
  await ctx.db.patch(place._id, { text: after, updatedAt: Date.now() });
  await logPlaceChange(ctx, { placeId: place.placeId, source, quote, before: place.text, after });
  return true;
}

/** Makes a place with an empty text. The caller has checked that the name key is free. The name is trimmed and cut. */
export async function createPlace(ctx: { db: DatabaseWriter }, name: string, text = ""): Promise<Doc<"places">> {
  const now = Date.now();
  const id = await ctx.db.insert("places", { placeId: crypto.randomUUID(), name: name.trim().replace(/\s+/g, " ").slice(0, PLACE_NAME_MAX).trim(), text, createdAt: now, updatedAt: now });
  return (await ctx.db.get(id))!;
}
