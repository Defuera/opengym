import { ConvexError, v } from "convex/values";
import { mutation } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { contextByItemId } from "../lib/db";
import { markFactsChanged } from "../lib/factsChanged";
import { parseOrThrow } from "../lib/validate";
import { ContextInputSchema, ContextPatchSchema } from "../model/schema";

/** Create a context note with a client-made itemId. Resending the same itemId changes nothing. */
export const create = mutation({
  args: { token: v.string(), itemId: v.string(), text: v.string(), topic: v.string() },
  handler: async (ctx, { token, itemId, ...input }) => {
    requireToken(token);
    if (!itemId || itemId.length > 100) throw new ConvexError("itemId: must be 1 to 100 characters");
    const valid = parseOrThrow(ContextInputSchema, input, "context");
    if (await contextByItemId(ctx, itemId)) return itemId;
    await ctx.db.insert("context", { itemId, ...valid, active: true, source: "user", createdAt: Date.now() });
    await markFactsChanged(ctx);
    return itemId;
  },
});

/** Switch a note on or off, or change its text. */
export const update = mutation({
  args: { token: v.string(), itemId: v.string(), active: v.optional(v.boolean()), text: v.optional(v.string()) },
  handler: async (ctx, { token, itemId, ...patch }) => {
    requireToken(token);
    const valid = parseOrThrow(ContextPatchSchema, patch, "context");
    const old = await contextByItemId(ctx, itemId);
    if (!old) throw new ConvexError(`context item not found: ${itemId}`);
    await ctx.db.patch(old._id, valid);
    await markFactsChanged(ctx);
    return itemId;
  },
});

/** Delete a context note. No error if it is already gone. */
export const remove = mutation({
  args: { token: v.string(), itemId: v.string() },
  handler: async (ctx, { token, itemId }) => {
    requireToken(token);
    const old = await contextByItemId(ctx, itemId);
    if (!old) return false;
    await ctx.db.delete(old._id);
    await markFactsChanged(ctx);
    return true;
  },
});
