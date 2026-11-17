import { v } from "convex/values";
import type { Doc } from "../_generated/dataModel";
import { query } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { allGoals, allSessions, sessionBySessionId, toSession } from "../lib/db";
import { toLimit } from "../lib/limitsDb";
import { focusPartsFromGoals } from "../model/rules/focusParts";
import { limitsLoadedBy } from "../model/rules/limits";
import { loadForDays } from "../model/rules/load";
import type { Session } from "../model/schema";

const STATUS_ORDER = { active: 0, improving: 1, cleared: 2 } as const;
const MAX_CHECKINS = 20;

/** "Gym, Upper" or "Cycling". */
const sessionLabel = (s: Session) => (s.kind === "gym" ? (s.focus ? `${s.type}, ${s.focus}` : s.type) : s.type);

/** Newest date first; records without a date last; then newest written first. */
const recordOrder = (a: Doc<"records">, b: Doc<"records">) => (b.date ?? "").localeCompare(a.date ?? "") || b._creationTime - a._creationTime;

/** Everything the "About me" screen shows. Read model computed on read from facts. */
export const get = query({
  args: { token: v.string() },
  handler: async (ctx, { token }) => {
    requireToken(token);
    const limitDocs = (await ctx.db.query("limits").collect()).sort((a, b) => STATUS_ORDER[a.status] - STATUS_ORDER[b.status] || a.title.localeCompare(b.title));
    const sessions = await allSessions(ctx);
    const byId = new Map(sessions.map((s) => [s.id, s]));
    const limits = [];
    for (const d of limitDocs) {
      const records = (await ctx.db.query("records").withIndex("by_limitId", (q) => q.eq("limitId", d.limitId)).collect()).sort(recordOrder);
      const checkins = (await ctx.db.query("checkins").withIndex("by_limitId", (q) => q.eq("limitId", d.limitId)).collect()).sort((a, b) => b.at - a.at || b._creationTime - a._creationTime).slice(0, MAX_CHECKINS);
      limits.push({
        ...toLimit(d),
        records: records.map((r) => ({ recordId: r.recordId, title: r.title, ...(r.date !== undefined ? { date: r.date } : {}), text: r.text })),
        checkins: checkins.map((c) => {
          const s = c.sessionId !== undefined ? byId.get(c.sessionId) : undefined;
          return { checkinId: c.checkinId, at: c.at, feeling: c.feeling, ...(c.sessionId !== undefined ? { sessionId: c.sessionId } : {}), ...(s ? { sessionLabel: sessionLabel(s) } : {}) };
        }),
      });
    }
    const now = Date.now();
    return {
      limits,
      load: { d14: loadForDays(sessions, 14, now), d90: loadForDays(sessions, 90, now) },
      focusParts: focusPartsFromGoals(await allGoals(ctx)) as string[],
    };
  },
});

/** Non-cleared limits that this session loaded and that have no check-in for it yet. */
export const askAfter = query({
  args: { token: v.string(), sessionId: v.string() },
  handler: async (ctx, { token, sessionId }) => {
    requireToken(token);
    const doc = await sessionBySessionId(ctx, sessionId);
    if (!doc) return [];
    const answered = new Set((await ctx.db.query("checkins").withIndex("by_sessionId", (q) => q.eq("sessionId", sessionId)).collect()).map((c) => c.limitId));
    const limits = (await ctx.db.query("limits").collect()).map(toLimit);
    return limitsLoadedBy(toSession(doc), limits)
      .filter((l) => !answered.has(l.limitId))
      .sort((a, b) => a.title.localeCompare(b.title))
      .map((l) => ({ limitId: l.limitId, title: l.title, part: l.part as string }));
  },
});
