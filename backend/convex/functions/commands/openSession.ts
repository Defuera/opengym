import { ConvexError, v } from "convex/values";
import { mutation } from "../_generated/server";
import { requireUser } from "../lib/auth";
import { OPEN_SESSION_MAX_EXERCISES, OPEN_SESSION_MAX_SETS } from "../model/openSession";
import { openSessionFields } from "../schema";

/**
 * The app stores the open session as it is on the phone (ADR-028). There is at most one: a put replaces the row, whatever session it
 * held. The app's copy always wins, because the person's hands are on it. Returns the new `rev`.
 * This is not a fact: a session becomes a fact when the app finishes it and sends commands/sessions:save.
 */
export const put = mutation({
  args: { token: v.string(), session: v.object(openSessionFields) },
  handler: async (ctx, { token, session }): Promise<number> => {
    const userId = await requireUser(ctx, token);
    if (session.id.length < 1 || session.id.length > 100) throw new ConvexError("id: must be 1 to 100 characters");
    if (session.exercises.length > OPEN_SESSION_MAX_EXERCISES) throw new ConvexError(`exercises: at most ${OPEN_SESSION_MAX_EXERCISES}`);
    if (session.exercises.some((e) => e.sets.length > OPEN_SESSION_MAX_SETS)) throw new ConvexError(`sets: at most ${OPEN_SESSION_MAX_SETS} for one exercise`);
    const old = await ctx.db.query("openSession").first();
    const rev = (old?.rev ?? 0) + 1;
    const row = { ...session, userId, rev, updatedAt: Date.now(), updatedBy: "app" as const };
    if (old) await ctx.db.replace(old._id, row);
    else await ctx.db.insert("openSession", row);
    return rev;
  },
});

/** The session `id` ended (finished or discarded): the row goes. Another open session is left alone. Idempotent. */
export const clear = mutation({
  args: { token: v.string(), id: v.string() },
  handler: async (ctx, { token, id }): Promise<void> => {
    const userId = await requireUser(ctx, token);
    const old = await ctx.db.query("openSession").first();
    if (old && old.id === id) await ctx.db.delete(old._id);
  },
});
