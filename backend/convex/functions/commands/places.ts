import { ConvexError, v } from "convex/values";
import { mutation } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { PLACE_NAME_MAX, PLACE_TEXT_MAX, placeKey } from "../lib/placeFields";
import { allPlaces, logPlaceChange, placeByPlaceId } from "../lib/placesDb";

/**
 * The user makes or edits a place (ADR-021). Idempotent upsert by the client-made `placeId` (1..100). `name` is 1..30 after trim;
 * `text` (the equipment, free text, 0..1500) is optional: left out, the stored text stays. Rejects a name whose key
 * (trim, lower case, inner spaces collapsed) belongs to another placeId. A change of the text logs a placeChanges row with source "user".
 */
export const save = mutation({
  args: { token: v.string(), placeId: v.string(), name: v.string(), text: v.optional(v.string()) },
  handler: async (ctx, { token, placeId, name, text }): Promise<string> => {
    requireToken(token);
    if (placeId.length < 1 || placeId.length > 100) throw new ConvexError("placeId: must be 1 to 100 characters");
    const clean = name.trim().replace(/\s+/g, " ");
    if (clean.length < 1 || clean.length > PLACE_NAME_MAX) throw new ConvexError(`name: must be 1 to ${PLACE_NAME_MAX} characters`);
    if (text !== undefined && text.length > PLACE_TEXT_MAX) throw new ConvexError(`text: must be at most ${PLACE_TEXT_MAX} characters`);
    const key = placeKey(clean);
    if ((await allPlaces(ctx)).some((p) => p.placeId !== placeId && placeKey(p.name) === key)) throw new ConvexError(`name: a place called "${clean}" exists already`);
    const old = await placeByPlaceId(ctx, placeId);
    const now = Date.now();
    if (!old) {
      const body = text?.trim() ?? "";
      await ctx.db.insert("places", { placeId, name: clean, text: body, createdAt: now, updatedAt: now });
      if (body) await logPlaceChange(ctx, { placeId, source: "user", quote: body, before: "", after: body });
      return placeId;
    }
    const after = text === undefined ? old.text : text.trim();
    if (old.name === clean && old.text === after) return placeId; // resend, nothing changed
    await ctx.db.patch(old._id, { name: clean, text: after, updatedAt: now });
    if (after !== old.text) await logPlaceChange(ctx, { placeId, source: "user", quote: after, before: old.text, after });
    return placeId;
  },
});
