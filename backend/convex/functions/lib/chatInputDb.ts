import type { QueryCtx } from "../_generated/server";
import { liveSessionDocs, toContextItem, toGoal, toSession, messageByMessageId, threadByThreadId } from "./db";
import { limitsForAi } from "./limitsDb";
import { coachEntries, entryInViewImageFiles } from "./entriesDb";
import { fileByFileId } from "./files";
import { CHAT_CONTEXT_ITEMS, CHAT_GOALS, CHAT_HISTORY_MESSAGES, CHAT_OTHER_THREADS, CHAT_RECENT_SESSIONS } from "../model/chatInput";

/**
 * Bounded input for one coach turn, read in one transaction (ADR-012). Null if the thread or message is gone.
 * Read by the coach turn (jobs/coachTurn:input).
 */
export async function readChatInput(ctx: Pick<QueryCtx, "db">, threadId: string, messageId: string, entryId?: string) {
  const thread = await threadByThreadId(ctx, threadId);
  const trigger = await messageByMessageId(ctx, messageId);
  if (!thread || !trigger) return null;
  if (trigger.voice === "pending" || trigger.voice === "failed") return null; // a voice message gets its reply only after the transcript is stored
  const recent = await ctx.db
    .query("messages")
    .withIndex("by_threadId", (q) => q.eq("threadId", threadId).lte("_creationTime", trigger._creationTime))
    .order("desc")
    .take(CHAT_HISTORY_MESSAGES);
  // A voice message without its transcript has no text yet; it is not part of the history.
  const history = recent.reverse().filter((m) => m.voice !== "pending" && m.voice !== "failed").map((m) => ({ role: m.role, content: m.text }));

  const threads = await ctx.db.query("threads").withIndex("by_updatedAt").order("desc").take(40);
  const otherThreads = threads.filter((t) => t.threadId !== threadId && t.summary.trim()).slice(0, CHAT_OTHER_THREADS).map((t) => ({ title: t.title, summary: t.summary }));

  const sessions = (await liveSessionDocs(ctx, { order: "desc", limit: CHAT_RECENT_SESSIONS })).reverse().map(toSession);
  const goalDocs = await ctx.db.query("goals").withIndex("by_createdAt").order("desc").take(200);
  const goals = goalDocs.filter((g) => g.status === "active").slice(0, CHAT_GOALS).reverse().map(toGoal);
  const contextDocs = await ctx.db.query("context").withIndex("by_createdAt").order("desc").take(200);
  const context = contextDocs.filter((c) => c.active).slice(0, CHAT_CONTEXT_ITEMS).reverse().map(toContextItem);

  const files = [];
  // The files of this message and of the earlier user messages still in the history (newest 6), so a photo stays visible in later turns.
  const threadFileIds = [...new Set(recent.filter((m) => m.role === "user").flatMap((m) => m.fileIds ?? []).concat(trigger.fileIds))].slice(-6);
  for (const id of threadFileIds) {
    const f = await fileByFileId(ctx, id);
    if (f && f.kind !== "audio") files.push({ fileId: f.fileId, storageId: f.storageId, name: f.name, mime: f.mime, size: f.size, kind: f.kind, createdAt: f.createdAt });
  }
  const now = Date.now();
  const entries = await coachEntries(ctx, now);
  const entryImages = await entryInViewImageFiles(ctx, entryId);
  return {
    history,
    data: { otherThreads, sessions, goals, context, limits: await limitsForAi(ctx), entries },
    files,
    entryImages,
  };
}
