import { v } from "convex/values";
import type { QueryCtx } from "../_generated/server";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { providerFor, runAiJob } from "../lib/ai";
import { allSessions, entryByEntryId, messageByMessageId, threadByThreadId } from "../lib/db";
import { readChatInput } from "../lib/chatInputDb";
import { executeActions } from "../lib/coachToolsDb";
import { logThreadContent } from "../lib/logDraftDb";
import { proposalQuestion } from "../lib/proposalDb";
import { knownCategories } from "../lib/categoriesDb";
import { loadEntryImages } from "../lib/entriesDb";
import { fileByFileId, loadAttachment } from "../lib/files";
import { coachQuestion } from "../lib/messageFields";
import { allPlaces } from "../lib/placesDb";
import { liveProgramDocs } from "../lib/programsDb";
import { coachTurnJob } from "../model/ai/jobs/coachTurn";
import { type AttachedFile, assembleCoachContext } from "../model/coachContext";
import { turnScreen } from "../model/coachTurnInput";
import { LOG_NO_AI, LOG_NO_PHOTO, LOG_UNREAD, type StoredLogDraft, logQuestion, plainLogDraft } from "../model/logDraft";
import { dayWithWeekday } from "../model/logDate";
import { localDate } from "../model/program";
import { programsForCoach } from "../model/programForCoach";
import { truncate } from "../model/rules/util";

const LOG_FILES_MAX = 10;

/**
 * The coach turn (ADR-032): one chat answer with functions. Scheduled by commands/messages:send for a message sent from the session,
 * an exercise or the log chat. Input: what a chat reply reads (lib/chatInputDb.ts) plus the screen, read by the server now: the open session
 * with exercise ids, done flags and rev, the exercise in view, the session's place and every place, the entry and the programs.
 */
/** The log chat (ADR-032) sees every message and file of its thread, not the last few, and the open draft it made. */
async function logInput(ctx: QueryCtx, threadId: string, upTo: number) {
  const content = await logThreadContent(ctx, threadId, upTo);
  const files = [];
  for (const id of content.fileIds.slice(-LOG_FILES_MAX)) {
    const f = await fileByFileId(ctx, id);
    if (f && f.kind !== "audio") files.push({ fileId: f.fileId, storageId: f.storageId, name: f.name, mime: f.mime, size: f.size, kind: f.kind, createdAt: f.createdAt });
  }
  const last = (await ctx.db.query("messages").withIndex("by_threadId", (q) => q.eq("threadId", threadId)).order("desc").filter((q) => q.neq(q.field("proposal"), undefined)).first())?.proposal;
  const open = last && last.type === "log" && last.appliedAt === undefined ? (last as StoredLogDraft) : null;
  const draft = open ? { kind: open.kind, ...(open.color ? { color: open.color } : {}), summary: open.summary, at: new Date(open.at).toISOString(), ...(open.session ? { session: open.session } : {}), ...(open.goal ? { goal: open.goal } : {}), ...(open.limit ? { limit: open.limit } : {}), ...(open.note ? { note: open.note } : {}) } : null;
  return { files, draft, categories: await knownCategories(ctx), photosOnly: !content.text.trim() && files.length > 0 && files.every((f) => f.kind === "image") };
}

export const input = internalQuery({
  args: { threadId: v.string(), messageId: v.string() },
  handler: async (ctx, { threadId, messageId }) => {
    const chat = await readChatInput(ctx, threadId, messageId);
    const trigger = await messageByMessageId(ctx, messageId);
    if (!chat || !trigger) return null;
    const hint = trigger.context ?? {};
    const row = await ctx.db.query("openSession").first();
    const places = await allPlaces(ctx);
    const screen = turnScreen({ screen: hint.screen, row, exerciseId: hint.exerciseId, places, placeId: hint.placeId });
    const entry = hint.entryId ? await entryByEntryId(ctx, hint.entryId) : null;
    const programs = programsForCoach(await liveProgramDocs(ctx), await allSessions(ctx), localDate(Date.now()));
    const isLog = hint.screen === "log";
    const log = isLog ? await logInput(ctx, threadId, trigger._creationTime) : null;
    const turn = {
      ...screen,
      ...(log ? { today: dayWithWeekday(Date.now()), now: new Date().toISOString(), ...(log.draft ? { currentLogDraft: log.draft } : {}), ...(log.categories.length > 0 ? { categoriesInUse: log.categories } : {}) } : {}),
      ...(entry ? { entryInView: { entryId: entry.entryId, text: entry.text, at: new Date(entry.at).toISOString(), files: entry.fileIds.length } } : {}),
      ...(programs.length > 0 ? { programsThePersonFollows: programs } : {}),
      ...(trigger.fileIds.length > 0 ? { attachedToThisMessage: chat.files.filter((f) => trigger.fileIds.includes(f.fileId)).map((f) => f.name) } : {}),
    };
    return { chat: log ? { ...chat, files: log.files } : chat, turn, log: log ? { photosOnly: log.photosOnly } : null, base: { turnId: messageId, ...(row ? { openSessionId: row.id, rev: row.rev } : {}) } };
  },
});

/**
 * Does the actions and stores the assistant message with the text, what each action did and the question, in ONE transaction.
 * Idempotent by the turn (the user message id) and the action id: a second run of the same turn changes nothing and returns the
 * results stored the first time. Null when the thread is gone.
 */
export const save = internalMutation({
  args: {
    threadId: v.string(),
    turnId: v.string(),
    openSessionId: v.optional(v.string()),
    rev: v.optional(v.number()),
    message: v.string(),
    actions: v.array(v.any()),
    question: v.optional(coachQuestion),
    sources: v.array(v.string()),
    /** The log chat had no AI answer: code makes the draft, a plain note of kind "other" (ADR-032). */
    plainLog: v.optional(v.boolean()),
  },
  handler: async (ctx, { threadId, turnId, openSessionId, rev, message, actions, question, sources, plainLog }) => {
    const thread = await threadByThreadId(ctx, threadId);
    if (!thread) return null;
    const now = Date.now();
    const pending = Math.max(0, thread.pending - 1);
    const done = await ctx.db.query("messages").withIndex("by_turnId", (q) => q.eq("turnId", turnId)).first();
    if (done) {
      await ctx.db.patch(thread._id, { pending, status: pending > 0 ? "thinking" : "idle" });
      return done.actions ?? [];
    }
    const made = await executeActions(ctx, { turnId, ...(openSessionId !== undefined ? { openSessionId } : {}), ...(rev !== undefined ? { rev } : {}) }, actions);
    const { results } = made;
    let proposal = made.proposal;
    let questionText = question?.text;
    if (plainLog && !proposal) {
      const content = await logThreadContent(ctx, threadId);
      proposal = plainLogDraft(content.text, content.fileIds.length, now);
      questionText = "Save this as a plain note?";
    }
    // A proposal always carries its two fixed answers; the model's own answers are dropped (ADR-032).
    const asked = proposal ? (proposal.type === "log" ? logQuestion(questionText) : proposalQuestion(questionText)) : question;
    await ctx.db.insert("messages", { messageId: crypto.randomUUID(), threadId, role: "assistant", text: message, fileIds: [], sources, turnId, actions: results, ...(asked ? { question: asked } : {}), ...(proposal ? { proposal } : {}), createdAt: now });
    await ctx.db.patch(thread._id, { pending, status: pending > 0 ? "thinking" : "idle", error: undefined, updatedAt: now, lastMessage: truncate(message, 200) });
    return results;
  },
});

/** The coach_turn job: input -> AI pipeline (JSON, zod, one retry, fallback with no action) -> save. Any unexpected error fails the reply. */
export const run = internalAction({
  args: { threadId: v.string(), messageId: v.string() },
  handler: async (ctx, { threadId, messageId }): Promise<void> => {
    const data = await ctx.runQuery(internal.jobs.coachTurn.input, { threadId, messageId });
    if (!data) return;
    try {
      const provider = await providerFor(ctx);
      const supportsImages = !!provider?.supportsImages;
      const isLog = data.turn.screen === "log";
      if (isLog && data.log?.photosOnly && !supportsImages) {
        // Only photos and none can be read: a fixed message, and Done still saves a plain note.
        await ctx.runMutation(internal.jobs.coachTurn.save, { threadId, ...data.base, message: LOG_NO_PHOTO, actions: [], sources: [], plainLog: true });
        await ctx.scheduler.runAfter(0, internal.jobs.chat.summarise, { threadId });
        return;
      }
      const files: AttachedFile[] = [];
      for (const f of data.chat.files) {
        const a = await loadAttachment(ctx, f, supportsImages);
        if (a) files.push(a);
      }
      const coach = assembleCoachContext(data.chat.data, files, supportsImages, await loadEntryImages(ctx, data.chat.entryImages, supportsImages));
      const r = await runAiJob(ctx, coachTurnJob, { contextBlock: coach.contextBlock, history: data.chat.history, images: coach.images, turn: data.turn, limits: data.chat.data.limits });
      await ctx.runMutation(internal.jobs.coachTurn.save, {
        threadId,
        ...data.base,
        message: isLog && r.path !== "ai" ? (provider ? LOG_UNREAD : LOG_NO_AI) : r.value.message,
        actions: r.path === "ai" ? r.value.actions : [],
        ...(isLog && r.path !== "ai" && !provider ? { plainLog: true } : {}),
        ...(r.value.question ? { question: r.value.question } : {}),
        sources: r.path === "ai" ? coach.sources : [],
      });
    } catch (e) {
      console.error(`[coach_turn] failed: ${(e as Error).message}`);
      await ctx.runMutation(internal.jobs.chat.fail, { threadId, error: `The coach could not answer: ${truncate((e as Error).message, 120)}` });
      return;
    }
    await ctx.scheduler.runAfter(0, internal.jobs.chat.summarise, { threadId });
  },
});
