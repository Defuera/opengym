import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { providerFor, runAiJob } from "../lib/ai";
import { liveSessionDocs, toContextItem, toGoal, toSession, messageByMessageId, threadByThreadId } from "../lib/db";
import { activeLimits } from "../lib/limitsDb";
import { placeByPlaceId } from "../lib/placesDb";
import { markFactsChanged } from "../lib/factsChanged";
import { coachEntries, entryImageFiles, loadEntryImages } from "../lib/entriesDb";
import { fileByFileId, loadAttachment } from "../lib/files";
import { chatJob } from "../model/ai/jobs/chat";
import { extractFromChatJob } from "../model/ai/jobs/extractFromChat";
import { summariseThreadJob } from "../model/ai/jobs/summariseThread";
import { titleThreadJob } from "../model/ai/jobs/titleThread";
import { type AttachedFile, assembleCoachContext } from "../model/coachContext";
import { CHAT_CONTEXT_ITEMS, CHAT_GOALS, CHAT_HISTORY_MESSAGES, CHAT_OTHER_THREADS, CHAT_RECENT_SESSIONS } from "../model/chatInput";
import { truncate } from "../model/rules/util";
import { contextInput, goalInput } from "../lib/validators";

/** Bounds on what the coach reads (ADR-012): in model/chatInput.ts, so the eval runner reads the same numbers. */
export { CHAT_HISTORY_MESSAGES, CHAT_OTHER_THREADS, CHAT_RECENT_SESSIONS, CHAT_GOALS, CHAT_CONTEXT_ITEMS };
/** Titles/texts sent to extract_from_chat so it does not repeat itself. Dedupe against the whole database happens in code. */
export const CHAT_KNOWN_ITEMS = 50;
export const SUMMARY_MESSAGES = 30;

/** Bounded input for one coach reply, read in one transaction. Null if the thread or message is gone. */
export const input = internalQuery({
  args: { threadId: v.string(), messageId: v.string() },
  handler: async (ctx, { threadId, messageId }) => {
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

    // The title job runs only for the first user message of a thread the user has not named.
    const userMessages = await ctx.db.query("messages").withIndex("by_threadId", (q) => q.eq("threadId", threadId)).filter((q) => q.eq(q.field("role"), "user")).take(2);
    const titleJob = thread.titleSource === "auto" && userMessages.length === 1 && userMessages[0]!.messageId === messageId ? { currentTitle: thread.title } : null;

    const files = [];
    // The files of this message and of the earlier user messages still in the history (newest 6), so a photo stays visible in later turns.
    const threadFileIds = [...new Set(recent.filter((m) => m.role === "user").flatMap((m) => m.fileIds ?? []).concat(trigger.fileIds))].slice(-6);
    for (const id of threadFileIds) {
      const f = await fileByFileId(ctx, id);
      if (f && f.kind !== "audio") files.push({ fileId: f.fileId, storageId: f.storageId, name: f.name, mime: f.mime, size: f.size, kind: f.kind, createdAt: f.createdAt });
    }
    const place = thread.placeId !== undefined ? await placeByPlaceId(ctx, thread.placeId) : null;
    const now = Date.now();
    const entries = await coachEntries(ctx, now);
    const entryImages = await entryImageFiles(ctx, now);
    return {
      title: thread.title,
      titleJob,
      text: trigger.text,
      history,
      data: { otherThreads, sessions, goals, context, limits: await activeLimits(ctx), entries },
      files,
      entryImages,
      place: place ? { name: place.name, equipment: place.text } : null,
      knownContext: contextDocs.filter((c) => c.active).slice(0, CHAT_KNOWN_ITEMS).map((c) => c.text),
      knownGoals: goalDocs.slice(0, CHAT_KNOWN_ITEMS).map((g) => g.title),
    };
  },
});

/** Stores the assistant message and ends one pending reply. False if the thread was deleted meanwhile. */
export const saveReply = internalMutation({
  args: { threadId: v.string(), text: v.string(), sources: v.array(v.string()) },
  handler: async (ctx, { threadId, text, sources }): Promise<boolean> => {
    const thread = await threadByThreadId(ctx, threadId);
    if (!thread) return false;
    const now = Date.now();
    await ctx.db.insert("messages", { messageId: crypto.randomUUID(), threadId, role: "assistant", text, fileIds: [], sources, createdAt: now });
    const pending = Math.max(0, thread.pending - 1);
    await ctx.db.patch(thread._id, { pending, status: pending > 0 ? "thinking" : "idle", error: undefined, updatedAt: now, lastMessage: truncate(text, 200) });
    return true;
  },
});

/**
 * Stores the AI title. Only if the title is still the one the job read and the user has not named the thread,
 * so a rename (or a second automatic title) made meanwhile always wins.
 */
export const saveTitle = internalMutation({
  args: { threadId: v.string(), expectedTitle: v.string(), title: v.string() },
  handler: async (ctx, { threadId, expectedTitle, title }): Promise<boolean> => {
    const thread = await threadByThreadId(ctx, threadId);
    if (!thread || thread.titleSource !== "auto" || thread.title !== expectedTitle) return false;
    await ctx.db.patch(thread._id, { title });
    return true;
  },
});

/** The reply failed: end one pending reply and show a short error on the thread. The user's message stays. */
export const fail = internalMutation({
  args: { threadId: v.string(), error: v.string() },
  handler: async (ctx, { threadId, error }) => {
    const thread = await threadByThreadId(ctx, threadId);
    if (!thread) return;
    const pending = Math.max(0, thread.pending - 1);
    await ctx.db.patch(thread._id, { pending, status: pending > 0 ? "thinking" : "failed", error: truncate(error, 200) });
  },
});

/**
 * Stores what extract_from_chat found. These are proposals tagged source "ai" with the threadId, exactly as the old
 * backend did. Items already known (same text / same title, case-insensitive) are skipped; the check reads the database.
 */
export const saveExtracted = internalMutation({
  args: { threadId: v.string(), goals: v.array(goalInput), context: v.array(contextInput) },
  handler: async (ctx, { threadId, goals, context }): Promise<{ goals: number; context: number }> => {
    if (!(await threadByThreadId(ctx, threadId))) return { goals: 0, context: 0 };
    const knownCtx = new Set((await ctx.db.query("context").collect()).filter((c) => c.active).map((c) => c.text.toLowerCase()));
    const knownGoals = new Set((await ctx.db.query("goals").collect()).map((g) => g.title.toLowerCase()));
    const now = Date.now();
    let nc = 0;
    let ng = 0;
    for (const c of context) {
      if (knownCtx.has(c.text.toLowerCase())) continue;
      knownCtx.add(c.text.toLowerCase());
      await ctx.db.insert("context", { itemId: crypto.randomUUID(), text: c.text, topic: c.topic, active: true, source: "ai", threadId, createdAt: now });
      nc++;
    }
    for (const g of goals) {
      if (knownGoals.has(g.title.toLowerCase())) continue;
      knownGoals.add(g.title.toLowerCase());
      await ctx.db.insert("goals", { ...g, goalId: crypto.randomUUID(), status: "active", source: "ai", threadId, createdAt: now });
      ng++;
    }
    if (nc || ng) await markFactsChanged(ctx);
    return { goals: ng, context: nc };
  },
});

/**
 * The coach job. Scheduled by commands/messages:send. Order: build bounded context, chat, store the assistant
 * message (the app sees it now), title_thread (first message only), extract_from_chat, store proposals, schedule summarise_thread.
 */
export const reply = internalAction({
  args: { threadId: v.string(), messageId: v.string() },
  handler: async (ctx, { threadId, messageId }): Promise<void> => {
    const data = await ctx.runQuery(internal.jobs.chat.input, { threadId, messageId });
    if (!data) return;
    let kept: boolean;
    let replyText = "";
    try {
      const supportsImages = !!(await providerFor(ctx))?.supportsImages;
      const files: AttachedFile[] = [];
      for (const f of data.files) {
        const a = await loadAttachment(ctx, f, supportsImages);
        if (a) files.push(a);
      }
      const coach = assembleCoachContext(data.data, files, supportsImages, await loadEntryImages(ctx, data.entryImages, supportsImages));
      const r = await runAiJob(ctx, chatJob, { contextBlock: coach.contextBlock, history: data.history, images: coach.images, ...(data.place ? { place: data.place } : {}) });
      kept = await ctx.runMutation(internal.jobs.chat.saveReply, { threadId, text: r.value, sources: r.path === "ai" ? coach.sources : [] });
      replyText = r.value;
    } catch (e) {
      console.error(`[chat] reply failed: ${(e as Error).message}`);
      await ctx.runMutation(internal.jobs.chat.fail, { threadId, error: `The coach could not answer: ${truncate((e as Error).message, 120)}` });
      return;
    }
    if (!kept) return;
    if (data.titleJob) {
      try {
        const t = await runAiJob(ctx, titleThreadJob, { text: data.text, reply: replyText });
        if (t.path === "ai") await ctx.runMutation(internal.jobs.chat.saveTitle, { threadId, expectedTitle: data.titleJob.currentTitle, title: t.value.title });
      } catch (e) {
        console.error(`[chat] title failed: ${(e as Error).message}`); // the code title stays
      }
    }
    try {
      const x = await runAiJob(ctx, extractFromChatJob, { text: data.text, existingContext: data.knownContext, existingGoals: data.knownGoals });
      await ctx.runMutation(internal.jobs.chat.saveExtracted, { threadId, goals: x.value.goals, context: x.value.context });
    } catch (e) {
      console.error(`[chat] extraction failed: ${(e as Error).message}`); // the answer is already stored; proposals are optional
    }
    await ctx.scheduler.runAfter(0, internal.jobs.chat.summarise, { threadId });
  },
});

/** Bounded input for summarise_thread. */
export const summaryInput = internalQuery({
  args: { threadId: v.string() },
  handler: async (ctx, { threadId }) => {
    const thread = await threadByThreadId(ctx, threadId);
    if (!thread) return null;
    const recent = await ctx.db.query("messages").withIndex("by_threadId", (q) => q.eq("threadId", threadId)).order("desc").take(SUMMARY_MESSAGES);
    return { title: thread.title, messages: recent.reverse().filter((m) => m.voice !== "pending" && m.voice !== "failed").map((m) => ({ role: m.role, text: m.text })) };
  },
});

export const saveSummary = internalMutation({
  args: { threadId: v.string(), summary: v.string() },
  handler: async (ctx, { threadId, summary }) => {
    const thread = await threadByThreadId(ctx, threadId);
    if (thread) await ctx.db.patch(thread._id, { summary });
  },
});

/** summarise_thread job: the summary other threads' replies read. */
export const summarise = internalAction({
  args: { threadId: v.string() },
  handler: async (ctx, { threadId }): Promise<void> => {
    const input = await ctx.runQuery(internal.jobs.chat.summaryInput, { threadId });
    if (!input) return;
    const r = await runAiJob(ctx, summariseThreadJob, input);
    await ctx.runMutation(internal.jobs.chat.saveSummary, { threadId, summary: r.value.summary });
  },
});
