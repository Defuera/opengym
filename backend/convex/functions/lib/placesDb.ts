import type { DatabaseReader, DatabaseWriter } from "../_generated/server";
import type { Doc } from "../_generated/dataModel";
import { PLACE_NAME_MAX, PLACE_QUOTE_MAX, PLACE_TEXT_MAX, placeKey } from "./placeFields";

type Source = "feedback" | "note" | "chat" | "user" | "seed";

/** Every place. There are few (a gym, a home, a hotel), so one read is fine. Sorted by name. */
export async function allPlaces(ctx: { db: DatabaseReader }, userId: string): Promise<Doc<"places">[]> {
  const rows = await ctx.db.query("places").withIndex("by_user_and_placeId", (q) => q.eq("userId", userId)).collect();
  return rows.sort((a, b) => a.name.localeCompare(b.name));
}

export const placeByPlaceId = (ctx: { db: DatabaseReader }, userId: string, placeId: string) =>
  ctx.db.query("places").withIndex("by_user_and_placeId", (q) => q.eq("userId", userId).eq("placeId", placeId)).unique();

/** The place whose name has this key, or null. The name key is unique, so there is at most one. */
export async function placeByName(ctx: { db: DatabaseReader }, userId: string, name: string): Promise<Doc<"places"> | null> {
  const k = placeKey(name);
  return (await ctx.db.query("places").withIndex("by_user_and_placeId", (q) => q.eq("userId", userId)).collect()).find((p) => placeKey(p.name) === k) ?? null;
}

type Evidence = "person_said" | "seen_in_photo";

/** Appends one trace row for a change of a place text. The quote is the user's sentence, cut to the limit. */
export function logPlaceChange(ctx: { db: DatabaseWriter }, userId: string, o: { placeId: string; source: Source; quote: string; before: string; after: string; evidence?: Evidence }) {
  return ctx.db.insert("placeChanges", { userId, placeId: o.placeId, at: Date.now(), source: o.source, quote: o.quote.slice(0, PLACE_QUOTE_MAX), before: o.before, after: o.after, ...(o.evidence ? { evidence: o.evidence } : {}) });
}

/**
 * Sets the text of a place when it differs (cut to the limit) and logs the change. Returns true when it wrote.
 * `expectedBefore`: write only while the stored text is still that (a background job read it earlier; a newer edit wins).
 */
export async function setPlaceText(ctx: { db: DatabaseWriter }, userId: string, place: Doc<"places">, text: string, source: Source, quote: string, expectedBefore?: string, evidence?: Evidence): Promise<boolean> {
  const after = text.trim().slice(0, PLACE_TEXT_MAX);
  if (expectedBefore !== undefined && place.text !== expectedBefore) return false;
  if (after === place.text) return false;
  // A text is never a full list (ADR-032): any text is "partial"; an emptied text is "unknown" again.
  await ctx.db.patch(place._id, { text: after, knowledgeState: after ? "partial" : "unknown", updatedAt: Date.now() });
  await logPlaceChange(ctx, userId, { placeId: place.placeId, source, quote, before: place.text, after, ...(evidence ? { evidence } : {}) });
  return true;
}

/** Makes a place with an empty text. The caller has checked that the name key is free. The name is trimmed and cut. */
export async function createPlace(ctx: { db: DatabaseWriter }, userId: string, name: string, text = ""): Promise<Doc<"places">> {
  const now = Date.now();
  const id = await ctx.db.insert("places", { userId, placeId: crypto.randomUUID(), name: name.trim().replace(/\s+/g, " ").slice(0, PLACE_NAME_MAX).trim(), text, knowledgeState: text.trim() ? "partial" : "unknown", createdAt: now, updatedAt: now });
  return (await ctx.db.get(id))!;
}
