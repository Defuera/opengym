import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { allPlaces } from "../lib/placesDb";

/** Every place, sorted by name. The app subscribes to this (ADR-021). */
export const list = query({
  args: { token: v.string() },
  handler: async (ctx, { token }) => {
    requireToken(token);
    return (await allPlaces(ctx)).map((p) => ({ placeId: p.placeId, name: p.name, text: p.text, updatedAt: p.updatedAt }));
  },
});
