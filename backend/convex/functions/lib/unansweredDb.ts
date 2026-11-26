import type { Doc } from "../_generated/dataModel";
import type { QueryCtx } from "../_generated/server";

const LOOKBACK = 20;

/** A user message that waits for its transcript or failed to get one has no coach turn of its own. */
const hasOwnTurn = (m: Doc<"messages">) => m.voice !== "pending" && m.voice !== "failed";

/**
 * The file ids of the person's messages since the last assistant message, up to the trigger, oldest first (ADR-040).
 * One coach turn answers all of them, so a photo of an earlier unanswered message counts as attached to the trigger.
 */
export async function unansweredFileIds(ctx: Pick<QueryCtx, "db">, userId: string, threadId: string, trigger: Doc<"messages">): Promise<string[]> {
  const recent = await ctx.db
    .query("messages")
    .withIndex("by_user_and_threadId", (q) => q.eq("userId", userId).eq("threadId", threadId).lte("_creationTime", trigger._creationTime))
    .order("desc")
    .take(LOOKBACK);
  const ids: string[] = [];
  for (const m of recent) {
    if (m.role === "assistant" && m._id !== trigger._id) break;
    if (m.role === "user") ids.unshift(...(m.fileIds ?? []));
  }
  return [...new Set(ids)];
}

/** True when a newer user message of the thread will get its own coach turn, so the turn of `trigger` stays silent (ADR-040). */
export async function hasNewerUserMessage(ctx: Pick<QueryCtx, "db">, userId: string, threadId: string, trigger: Doc<"messages">): Promise<boolean> {
  const newer = await ctx.db
    .query("messages")
    .withIndex("by_user_and_threadId", (q) => q.eq("userId", userId).eq("threadId", threadId).gt("_creationTime", trigger._creationTime))
    .take(LOOKBACK);
  for (const m of newer) {
    if (m.role !== "user" || !hasOwnTurn(m)) continue;
    // A tap on "approve" that plain code answered has no coach turn.
    if (m.answer?.id === "approve" && (await ctx.db.query("messages").withIndex("by_user_and_turnId", (q) => q.eq("userId", userId).eq("turnId", m.messageId)).first())) continue;
    return true;
  }
  return false;
}
