import type { DatabaseReader, DatabaseWriter } from "../_generated/server";
import type { Doc } from "../_generated/dataModel";
import type { ContextItem, Entry, Goal, Session } from "../model/schema";
import { activityKey, normalizeSession } from "../model/sessionShape";

/** Fact docs use client-made `sessionId`/`goalId`/`itemId`; the model uses the contract's `id`. */

/** Reads a stored row. A legacy gym row (type "Upper", no focus) comes back as type "Gym", focus "Upper". */
export function toSession(d: Doc<"sessions">): Session {
  return normalizeSession({
    id: d.sessionId,
    kind: d.kind,
    type: d.type,
    ...(d.focus !== undefined ? { focus: d.focus } : {}),
    startedAt: d.startedAt,
    endedAt: d.endedAt,
    exercises: d.exercises,
    ...(d.minutes !== undefined ? { minutes: d.minutes } : {}),
    ...(d.distanceKm !== undefined ? { distanceKm: d.distanceKm } : {}),
    ...(d.note !== undefined ? { note: d.note } : {}),
    source: d.source,
    ...(d.importId !== undefined ? { importId: d.importId } : {}),
    ...(d.placeId !== undefined ? { placeId: d.placeId } : {}),
    ...(d.programId !== undefined ? { programId: d.programId } : {}),
    ...(d.programWeek !== undefined ? { programWeek: d.programWeek } : {}),
    ...(d.programSlot !== undefined ? { programSlot: d.programSlot } : {}),
    ...(d.programKey !== undefined ? { programKey: d.programKey } : {}),
  });
}

/** Model session -> stored doc (client id goes to `sessionId`). */
export function fromSession(s: Session): Omit<Doc<"sessions">, "_id" | "_creationTime"> {
  const { id, ...rest } = s;
  return { sessionId: id, ...rest };
}

export function toGoal(d: Doc<"goals">): Goal {
  return {
    id: d.goalId,
    title: d.title,
    kind: d.kind,
    ...(d.exercise !== undefined ? { exercise: d.exercise } : {}),
    ...(d.targetKg !== undefined ? { targetKg: d.targetKg } : {}),
    ...(d.sessionsPerWeek !== undefined ? { sessionsPerWeek: d.sessionsPerWeek } : {}),
    status: d.status,
    source: d.source,
    ...(d.threadId !== undefined ? { threadId: d.threadId } : {}),
    ...(d.importId !== undefined ? { importId: d.importId } : {}),
    createdAt: d.createdAt,
  };
}

export function toContextItem(d: Doc<"context">): ContextItem {
  return {
    id: d.itemId,
    text: d.text,
    topic: d.topic,
    active: d.active,
    source: d.source,
    ...(d.threadId !== undefined ? { threadId: d.threadId } : {}),
    ...(d.importId !== undefined ? { importId: d.importId } : {}),
    createdAt: d.createdAt,
  };
}

export function toEntry(d: Doc<"entries">): Entry {
  return { id: d.entryId, text: d.text, fileIds: d.fileIds, at: d.at, createdAt: d.createdAt };
}

/**
 * The row of an entry, MARKED OR NOT. Only code that must see a marked row uses this: commands/entries (save, remove, restore)
 * and jobs/purge. Every read for a user, a job or the coach uses `entryByEntryId`.
 */
export const entryRowByEntryId = (ctx: Reader, entryId: string) =>
  ctx.db.query("entries").withIndex("by_entryId", (q) => q.eq("entryId", entryId)).unique();

/** The live entry (not marked as deleted, ADR-020), or null. */
export async function entryByEntryId(ctx: Reader, entryId: string): Promise<Doc<"entries"> | null> {
  const d = await entryRowByEntryId(ctx, entryId);
  return d && d.deletedAt === undefined ? d : null;
}

/**
 * Live entries by `at` (ADR-020: rows marked as deleted are left out BEFORE the limit, so `limit` stays the count of live rows).
 * `from` and `to` bound `at` (both inclusive). The one way to list entries.
 */
export function liveEntryDocs(ctx: Reader, o: { order: "asc" | "desc"; from?: number; to?: number; limit?: number }): Promise<Doc<"entries">[]> {
  const q = ctx.db
    .query("entries")
    .withIndex("by_at", (r) => (o.from !== undefined ? (o.to !== undefined ? r.gte("at", o.from).lte("at", o.to) : r.gte("at", o.from)) : o.to !== undefined ? r.lte("at", o.to) : r))
    .order(o.order)
    .filter((f) => f.eq(f.field("deletedAt"), undefined));
  return o.limit === undefined ? q.collect() : q.take(o.limit);
}

type Reader = { db: DatabaseReader };

/**
 * Live sessions by `endedAt` (ADR-020: rows marked as deleted are left out BEFORE the limit, so `limit` stays the count of
 * live rows). `after` keeps only sessions that ended after it. The one way to list sessions.
 */
export function liveSessionDocs(ctx: Reader, o: { order: "asc" | "desc"; after?: number; limit?: number }): Promise<Doc<"sessions">[]> {
  const q = ctx.db
    .query("sessions")
    .withIndex("by_endedAt", (r) => (o.after !== undefined ? r.gt("endedAt", o.after) : r))
    .order(o.order)
    .filter((f) => f.eq(f.field("deletedAt"), undefined));
  return o.limit === undefined ? q.collect() : q.take(o.limit);
}

/** The FULL live history, oldest first. Code that computes numbers or applies limits reads this. */
export async function allSessions(ctx: Reader): Promise<Session[]> {
  return (await liveSessionDocs(ctx, { order: "asc" })).map(toSession);
}

export async function allGoals(ctx: Reader): Promise<Goal[]> {
  const docs = await ctx.db.query("goals").withIndex("by_createdAt").order("asc").collect();
  return docs.map(toGoal);
}

export async function allContext(ctx: Reader): Promise<ContextItem[]> {
  const docs = await ctx.db.query("context").withIndex("by_createdAt").order("asc").collect();
  return docs.map(toContextItem);
}

/**
 * The row of a session, MARKED OR NOT. Only code that must see a marked row uses this: commands/sessions (save, logText,
 * remove, restore), lib/importWrite and jobs/purge. Every read for a user, a job or the coach uses `sessionBySessionId`.
 */
export const sessionRowBySessionId = (ctx: Reader, sessionId: string) =>
  ctx.db.query("sessions").withIndex("by_sessionId", (q) => q.eq("sessionId", sessionId)).unique();

/** The live session (not marked as deleted, ADR-020), or null. */
export async function sessionBySessionId(ctx: Reader, sessionId: string): Promise<Doc<"sessions"> | null> {
  const d = await sessionRowBySessionId(ctx, sessionId);
  return d && d.deletedAt === undefined ? d : null;
}

export const goalByGoalId = (ctx: Reader, goalId: string) =>
  ctx.db.query("goals").withIndex("by_goalId", (q) => q.eq("goalId", goalId)).unique();

export const contextByItemId = (ctx: Reader, itemId: string) =>
  ctx.db.query("context").withIndex("by_itemId", (q) => q.eq("itemId", itemId)).unique();

/** Strip Convex system fields so a fact can be compared with what a client sent. */
export function withoutSystemFields<T extends { _id: unknown; _creationTime: number }>(doc: T): Omit<T, "_id" | "_creationTime"> {
  const { _id, _creationTime, ...rest } = doc;
  void _id;
  void _creationTime;
  return rest;
}

/** JSON with sorted keys, so two equal facts compare equal whatever their key order. */
export function stableJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`;
  if (value && typeof value === "object") {
    const o = value as Record<string, unknown>;
    return `{${Object.keys(o).sort().filter((k) => o[k] !== undefined).map((k) => `${JSON.stringify(k)}:${stableJson(o[k])}`).join(",")}}`;
  }
  return JSON.stringify(value) ?? "null";
}

export const threadByThreadId = (ctx: Reader, threadId: string) =>
  ctx.db.query("threads").withIndex("by_threadId", (q) => q.eq("threadId", threadId)).unique();

/** Deletes a thread and its messages (commands/threads:remove, commands/programs:remove). Goals and context items it produced stay: they are facts. */
export async function deleteThreadWithMessages(ctx: { db: DatabaseWriter }, thread: Doc<"threads">): Promise<void> {
  for (const m of await ctx.db.query("messages").withIndex("by_threadId", (q) => q.eq("threadId", thread.threadId)).collect()) await ctx.db.delete(m._id);
  await ctx.db.delete(thread._id);
}

export const messageByMessageId = (ctx: Reader, messageId: string) =>
  ctx.db.query("messages").withIndex("by_messageId", (q) => q.eq("messageId", messageId)).unique();

/** The key of a stored plan: the activity and the focus, each by `activityKey`. */
export const planKey = (activity: string, focus?: string) => ({ activityKey: activityKey(activity), focusKey: activityKey(focus ?? "") });

/**
 * The plan stored for an activity and focus, or null. A plan row from before ADR-016 has no activity key:
 * it is read as a Gym plan until the next rebuild replaces it (jobs/rebuild prunes it).
 */
export async function planFor(ctx: Reader, activity: string, focus?: string): Promise<Doc<"plans"> | null> {
  const k = planKey(activity, focus);
  const doc = await ctx.db.query("plans").withIndex("by_activity", (q) => q.eq("activityKey", k.activityKey).eq("focusKey", k.focusKey)).unique();
  if (doc || k.activityKey !== "gym" || !focus) return doc;
  const legacy = await ctx.db.query("plans").withIndex("by_focus", (q) => q.eq("focus", focus)).collect();
  return legacy.find((p) => p.activityKey === undefined) ?? null;
}

export const startRequestById = (ctx: Reader, requestId: string) =>
  ctx.db.query("startRequests").withIndex("by_requestId", (q) => q.eq("requestId", requestId)).unique();
