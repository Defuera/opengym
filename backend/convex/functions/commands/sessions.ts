import { v } from "convex/values";
import { mutation } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { sessionFields } from "../schema";

/** Idempotent write of one session, keyed by the client-made sessionId. */
export const save = mutation({
  args: { token: v.string(), session: v.object(sessionFields) },
  handler: async (ctx, { token, session }) => {
    requireToken(token);
    if (session.endedAt < session.startedAt) throw new Error("endedAt must not be before startedAt");
    if (session.kind === "activity" && session.exercises.length > 0) throw new Error("activity sessions must have no exercises");
    const old = await ctx.db.query("sessions").withIndex("by_sessionId", (q) => q.eq("sessionId", session.sessionId)).unique();
    if (old) await ctx.db.replace(old._id, session);
    else await ctx.db.insert("sessions", session);
    return session.sessionId;
  },
});

/** Delete one session by its client-made id. No error if it is already gone. */
export const remove = mutation({
  args: { token: v.string(), sessionId: v.string() },
  handler: async (ctx, { token, sessionId }) => {
    requireToken(token);
    const old = await ctx.db.query("sessions").withIndex("by_sessionId", (q) => q.eq("sessionId", sessionId)).unique();
    if (old) await ctx.db.delete(old._id);
    return old !== null;
  },
});
