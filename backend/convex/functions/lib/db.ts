import type { DatabaseReader } from "../_generated/server";
import type { Doc } from "../_generated/dataModel";
import type { ContextItem, Goal, Session } from "../model/schema";
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

type Reader = { db: DatabaseReader };

/** The FULL history, oldest first. Code that computes numbers or applies limits reads this. */
export async function allSessions(ctx: Reader): Promise<Session[]> {
  const docs = await ctx.db.query("sessions").withIndex("by_endedAt").order("asc").collect();
  return docs.map(toSession);
}

export async function allGoals(ctx: Reader): Promise<Goal[]> {
  const docs = await ctx.db.query("goals").withIndex("by_createdAt").order("asc").collect();
  return docs.map(toGoal);
}

export async function allContext(ctx: Reader): Promise<ContextItem[]> {
  const docs = await ctx.db.query("context").withIndex("by_createdAt").order("asc").collect();
  return docs.map(toContextItem);
}

export const sessionBySessionId = (ctx: Reader, sessionId: string) =>
  ctx.db.query("sessions").withIndex("by_sessionId", (q) => q.eq("sessionId", sessionId)).unique();

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
