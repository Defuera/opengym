import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireUser } from "../lib/auth";
import { allPlaces } from "../lib/placesDb";

/** Every place, sorted by name. The app subscribes to this (ADR-021). */
export const list = query({
  args: { token: v.string() },
  handler: async (ctx, { token }) => {
    const userId = await requireUser(ctx, token);
    return (await allPlaces(ctx, userId)).map((p) => ({ placeId: p.placeId, name: p.name, text: p.text, updatedAt: p.updatedAt }));
  },
});
