import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { runAiJob } from "../lib/ai";
import { threadByThreadId } from "../lib/db";
import { summariseThreadJob } from "../model/ai/jobs/summariseThread";
import { truncate } from "../model/rules/util";

/** Messages the thread summary reads. */
export const SUMMARY_MESSAGES = 30;

/** The reply failed: end one pending reply and show a short error on the thread. The user's message stays. */
export const fail = internalMutation({
  args: { userId: v.string(), threadId: v.string(), error: v.string() },
  handler: async (ctx, { userId, threadId, error }) => {
    const thread = await threadByThreadId(ctx, userId, threadId);
    if (!thread) return;
    const pending = Math.max(0, thread.pending - 1);
    await ctx.db.patch(thread._id, { pending, status: pending > 0 ? "thinking" : "failed", error: truncate(error, 200) });
  },
});

/** Bounded input for summarise_thread. */
export const summaryInput = internalQuery({
  args: { userId: v.string(), threadId: v.string() },
  handler: async (ctx, { userId, threadId }) => {
    const thread = await threadByThreadId(ctx, userId, threadId);
    if (!thread) return null;
    const recent = await ctx.db.query("messages").withIndex("by_threadId", (q) => q.eq("threadId", threadId)).order("desc").take(SUMMARY_MESSAGES);
    return { title: thread.title, messages: recent.reverse().filter((m) => m.voice !== "pending" && m.voice !== "failed").map((m) => ({ role: m.role, text: m.text })) };
  },
});

export const saveSummary = internalMutation({
  args: { userId: v.string(), threadId: v.string(), summary: v.string() },
  handler: async (ctx, { userId, threadId, summary }) => {
    const thread = await threadByThreadId(ctx, userId, threadId);
    if (thread) await ctx.db.patch(thread._id, { summary });
  },
});

/** summarise_thread job: the summary other threads' replies read. */
export const summarise = internalAction({
  args: { userId: v.string(), threadId: v.string() },
  handler: async (ctx, { userId, threadId }): Promise<void> => {
    const input = await ctx.runQuery(internal.jobs.chat.summaryInput, { userId, threadId });
    if (!input) return;
    const r = await runAiJob(ctx, userId, summariseThreadJob, input);
    await ctx.runMutation(internal.jobs.chat.saveSummary, { userId, threadId, summary: r.value.summary });
  },
});
