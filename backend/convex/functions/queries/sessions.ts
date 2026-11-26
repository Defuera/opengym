import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireUser } from "../lib/auth";
import { liveSessionDocs, sessionBySessionId, toSession, withoutUserId } from "../lib/db";
import { loadForPlan, loadForSession } from "../model/rules/load";
import { normalizeSession } from "../model/sessionShape";

/**
 * Newest first. The app subscribes to this, so every change arrives live.
 * A legacy gym row (type "Upper", no focus) is returned as type "Gym", focus "Upper".
 */
export const recent = query({
  args: { token: v.string(), limit: v.optional(v.number()) },
  handler: async (ctx, { token, limit }) => {
    const userId = await requireUser(ctx, token);
    const docs = await liveSessionDocs(ctx, userId, { order: "desc", limit: Math.min(limit ?? 20, 200) });
    return docs.map((d) => withoutUserId(normalizeSession(d)));
  },
});

/** Sessions that ended after `since` (epoch ms), oldest first. For the app's sync. */
export const since = query({
  args: { token: v.string(), since: v.number() },
  handler: async (ctx, { token, since }) => {
    const userId = await requireUser(ctx, token);
    const docs = await liveSessionDocs(ctx, userId, { order: "asc", after: since });
    return docs.map((d) => withoutUserId(normalizeSession(d)));
  },
});

/**
 * What one session loaded, for the body figure on its recap: muscle key -> level 0..3, every muscle key present.
 * Same level rule as the "About me" load (the busiest muscle of this session is the top). Null when the session does not exist or is marked as deleted.
 */
export const load = query({
  args: { token: v.string(), sessionId: v.string() },
  handler: async (ctx, { token, sessionId }) => {
    const userId = await requireUser(ctx, token);
    const doc = await sessionBySessionId(ctx, userId, sessionId);
    return doc ? loadForSession(toSession(doc)) : null;
  },
});

/**
 * What a planned session will load, for the body figure of an open session: muscle key -> level 0..3, every muscle key present.
 * Plain code, no stored data: per exercise the name, the number of rep sets and the planned minutes (time exercises). At most 30 exercises.
 */
export const planLoad = query({
  args: { token: v.string(), exercises: v.array(v.object({ name: v.string(), sets: v.number(), minutes: v.number() })) },
  handler: async (ctx, { token, exercises }) => {
    const userId = await requireUser(ctx, token);
    return loadForPlan(exercises.slice(0, 30).map((e) => ({ name: e.name.slice(0, 80), sets: Math.max(0, Math.min(20, e.sets)), minutes: Math.max(0, Math.min(600, e.minutes)) })));
  },
});
