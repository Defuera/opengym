import type { Doc } from "../_generated/dataModel";
import type { QueryCtx } from "../_generated/server";
import { localDate } from "../model/program";
import { messageByMessageId, threadByThreadId } from "./db";

type Reader = Pick<QueryCtx, "db">;

/** The one chat thread of the debrief of a session (ADR-041). The id is made from the session id, so a second open finds the first thread; ids are per user. */
export const debriefThreadId = (sessionId: string) => `debrief-${sessionId}`.slice(0, 100);
/** The first assistant message of that thread: the debrief itself. */
export const debriefMessageId = (sessionId: string) => `debrief-msg-${sessionId}`.slice(0, 100);

/** The debrief chat of a session: its thread id, and whether the person answered (a user message exists). Null when no thread was opened. */
export async function debriefState(ctx: Reader, userId: string, sessionId: string): Promise<{ threadId: string; answered: boolean } | null> {
  const threadId = debriefThreadId(sessionId);
  if (!(await threadByThreadId(ctx, userId, threadId))) return null;
  const answer = await ctx.db.query("messages").withIndex("by_user_and_threadId", (q) => q.eq("userId", userId).eq("threadId", threadId)).filter((q) => q.eq(q.field("role"), "user")).first();
  return { threadId, answered: answer !== null };
}

/** How many of the newest sessions are looked at for an answered debrief, and how old they may be. */
export const AFTER_SESSION_SESSIONS = 3;
export const AFTER_SESSION_DAYS = 14;

/**
 * What the person said after their last sessions, for the next plan and the next chat (ADR-041): the question of the debrief, the person's first
 * answer and the date, newest last. Only answered debriefs. `sessions` are the live sessions, oldest first. Every read is by the user id.
 */
export async function afterSession(ctx: Reader, userId: string, sessions: Pick<Doc<"sessions">, "sessionId" | "endedAt" | "type" | "focus">[], now: number, timeZone?: string) {
  const out: { date: string; session: string; question: string; answer: string }[] = [];
  for (const s of sessions.filter((x) => x.endedAt > now - AFTER_SESSION_DAYS * 86_400_000).slice(-AFTER_SESSION_SESSIONS)) {
    const threadId = debriefThreadId(s.sessionId);
    if (!(await threadByThreadId(ctx, userId, threadId))) continue;
    const rows = await ctx.db.query("messages").withIndex("by_user_and_threadId", (q) => q.eq("userId", userId).eq("threadId", threadId)).order("asc").take(8);
    const asked = rows.find((m) => m.role === "assistant");
    const answer = rows.find((m) => m.role === "user" && m.text.trim());
    if (!asked?.question || !answer) continue;
    out.push({ date: localDate(s.endedAt, timeZone), session: s.focus ? `${s.type} ${s.focus}` : s.type, question: asked.question.text, answer: answer.text.trim().slice(0, 300) });
  }
  return out;
}

/** True when the first assistant message of the debrief thread exists already. */
export const debriefMessageExists = (ctx: Reader, userId: string, sessionId: string) => messageByMessageId(ctx, userId, debriefMessageId(sessionId));
