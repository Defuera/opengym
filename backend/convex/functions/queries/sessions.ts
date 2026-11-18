import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { sessionBySessionId, toSession } from "../lib/db";
import { loadForSession } from "../model/rules/load";
import { normalizeSession } from "../model/sessionShape";

/**
 * Newest first. The app subscribes to this, so every change arrives live.
 * A legacy gym row (type "Upper", no focus) is returned as type "Gym", focus "Upper".
 */
export const recent = query({
  args: { token: v.string(), limit: v.optional(v.number()) },
  handler: async (ctx, { token, limit }) => {
    requireToken(token);
    const docs = await ctx.db.query("sessions").withIndex("by_endedAt").order("desc").take(Math.min(limit ?? 20, 200));
    return docs.map(normalizeSession);
  },
});

/** Sessions that ended after `since` (epoch ms), oldest first. For the app's sync. */
export const since = query({
  args: { token: v.string(), since: v.number() },
  handler: async (ctx, { token, since }) => {
    requireToken(token);
    const docs = await ctx.db.query("sessions").withIndex("by_endedAt", (q) => q.gt("endedAt", since)).order("asc").collect();
    return docs.map(normalizeSession);
  },
});

/**
 * What one session loaded, for the body figure on its recap: muscle key -> level 0..3, every muscle key present.
 * Same level rule as the "About me" load (the busiest muscle of this session is the top). Null when the session does not exist.
 */
export const load = query({
  args: { token: v.string(), sessionId: v.string() },
  handler: async (ctx, { token, sessionId }) => {
    requireToken(token);
    const doc = await sessionBySessionId(ctx, sessionId);
    return doc ? loadForSession(toSession(doc)) : null;
  },
});
