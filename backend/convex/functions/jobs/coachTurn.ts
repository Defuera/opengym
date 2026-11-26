import { v } from "convex/values";
import type { QueryCtx } from "../_generated/server";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { providerFor, runAiJob } from "../lib/ai";
import { programTurnState, startProgramProposal } from "../lib/programChatDb";
import { allContext, allGoals, allSessions, entryByEntryId, liveSessionDocs, messageByMessageId, threadByThreadId } from "../lib/db";
import { afterSession, AFTER_SESSION_DAYS } from "../lib/debriefDb";
import { toLimit } from "../lib/limitsDb";
import { hasNewerUserMessage, unansweredFileIds } from "../lib/unansweredDb";
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
import { editablesForTurn, turnScreen } from "../model/coachTurnInput";
import { goalFromText } from "../model/goalDraft";
import { LOG_NO_AI, LOG_NO_PHOTO, LOG_UNREAD, type StoredLogDraft, logQuestion, plainLogDraft, plainPartNoAi } from "../model/logDraft";
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
/** The open log draft of the thread, as the coach reads it (currentLogDraft), on every screen; null when the last proposal is not an open log draft. */
async function openLogDraft(ctx: QueryCtx, userId: string, threadId: string) {
  const last = (await ctx.db.query("messages").withIndex("by_user_and_threadId", (q) => q.eq("userId", userId).eq("threadId", threadId)).order("desc").filter((q) => q.neq(q.field("proposal"), undefined)).first())?.proposal;
  const open = last && last.type === "log" && last.appliedAt === undefined ? (last as StoredLogDraft) : null;
  return open ? { kind: open.kind, ...(open.color ? { color: open.color } : {}), summary: open.summary, at: new Date(open.at).toISOString(), ...(open.session ? { session: open.session } : {}), ...(open.goal ? { goal: open.goal } : {}), ...(open.limit ? { limit: open.limit } : {}), ...(open.note ? { note: open.note } : {}) } : null;
}

/** The log chat (ADR-032) sees every message and file of its thread, not the last few. Other chats keep the files of a chat reply. */
async function logInput(ctx: QueryCtx, userId: string, threadId: string, upTo: number) {
  const content = await logThreadContent(ctx, userId, threadId, upTo);
  const files = [];
  for (const id of content.fileIds.slice(-LOG_FILES_MAX)) {
    const f = await fileByFileId(ctx, userId, id);
    if (f && f.kind !== "audio") files.push({ fileId: f.fileId, storageId: f.storageId, name: f.name, mime: f.mime, size: f.size, kind: f.kind, createdAt: f.createdAt });
  }
  return { files, photosOnly: !content.text.trim() && files.length > 0 && files.every((f) => f.kind === "image") };
}

export const input = internalQuery({
  args: { userId: v.string(), threadId: v.string(), messageId: v.string() },
  handler: async (ctx, { userId, threadId, messageId }) => {
    const trigger = await messageByMessageId(ctx, userId, messageId);
    const hint = trigger?.context ?? {};
    // Photos go with the turn only when they belong to the thread's messages or to the entry in view.
    const chat = await readChatInput(ctx, userId, threadId, messageId, hint.entryId);
    if (!chat || !trigger) return null;
    const row = await ctx.db.query("openSession").withIndex("by_user", (q) => q.eq("userId", userId)).unique();
    const places = await allPlaces(ctx, userId);
    const thread = await threadByThreadId(ctx, userId, threadId);
    // A thread about a program is the program chat whatever the message says (a program thread is the program chat whatever the context says).
    const aboutProgram = thread?.about?.kind === "program";
    const screen = turnScreen({ screen: aboutProgram ? "program" : hint.screen, row, exerciseId: hint.exerciseId, places, placeId: hint.placeId ?? thread?.placeId });
    const programId = hint.programId ?? thread?.about?.id;
    const program = screen.screen === "program" ? await programTurnState(ctx, userId, threadId, programId, Date.now()) : null;
    const entry = hint.entryId ? await entryByEntryId(ctx, userId, hint.entryId) : null;
    const programs = programsForCoach(await liveProgramDocs(ctx, userId), await allSessions(ctx, userId), localDate(Date.now(), chat.data.timeZone));
    const isLog = hint.screen === "log";
    const draft = await openLogDraft(ctx, userId, threadId);
    const categories = await knownCategories(ctx, userId);
    const log = isLog ? await logInput(ctx, userId, threadId, trigger._creationTime) : null;
    const editables = editablesForTurn({ goals: await allGoals(ctx, userId), limits: (await ctx.db.query("limits").withIndex("by_user_and_limitId", (q) => q.eq("userId", userId)).collect()).map(toLimit), notes: await allContext(ctx, userId), goalId: hint.goalId, limitId: hint.limitId, noteId: hint.noteId, part: hint.part });
    const unanswered = await unansweredFileIds(ctx, userId, threadId, trigger); // the files of every message this turn answers (ADR-040)
    const answers = await afterSession(ctx, userId, await liveSessionDocs(ctx, userId, { order: "asc", after: Date.now() - AFTER_SESSION_DAYS * 86_400_000 }), Date.now(), chat.data.timeZone);
    const turn = {
      ...screen,
      ...(answers.length > 0 ? { afterSession: answers } : {}),
      ...editables,
      ...(program ?? {}),
      // What any log needs, on every screen: the day, the time, the categories in use and the open draft.
      today: dayWithWeekday(Date.now(), chat.data.timeZone),
      now: new Date().toISOString(),
      ...(draft ? { currentLogDraft: draft } : {}),
      ...(categories.length > 0 ? { categoriesInUse: categories } : {}),
      ...(entry ? { entryInView: { entryId: entry.entryId, text: entry.text, at: new Date(entry.at).toISOString(), files: entry.fileIds.length } } : {}),
      ...(programs.length > 0 ? { programsThePersonFollows: programs } : {}),
      ...(unanswered.length > 0 ? { attachedToThisMessage: chat.files.filter((f) => unanswered.includes(f.fileId)).map((f) => f.name) } : {}),
    };
    return { chat: log ? { ...chat, files: log.files } : chat, turn, log: log ? { photosOnly: log.photosOnly } : null, base: { turnId: messageId, screen: screen.screen, ...(row ? { openSessionId: row.id, rev: row.rev } : {}) } };
  },
});

/**
 * Does the actions and stores the assistant message with the text, what each action did and the question, in ONE transaction.
 * Idempotent by the turn (the user message id) and the action id: a second run of the same turn changes nothing and returns the
 * results stored the first time. Null when the thread is gone.
 */
export const save = internalMutation({
  args: {
    userId: v.string(),
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
    /** The screen the message came from ("log" makes an entry on Done; any other draft writes its parts only). */
    screen: v.optional(v.string()),
    /** The goal or note chat had no AI answer: code drafts the person's words as a goal or a note. */
    plainPart: v.optional(v.union(v.literal("goal"), v.literal("note"))),
  },
  handler: async (ctx, { userId, threadId, turnId, openSessionId, rev, message, actions, question, sources, plainLog, screen, plainPart }) => {
    const thread = await threadByThreadId(ctx, userId, threadId);
    if (!thread) return null;
    const now = Date.now();
    const pending = Math.max(0, thread.pending - 1);
    const done = await ctx.db.query("messages").withIndex("by_user_and_turnId", (q) => q.eq("userId", userId).eq("turnId", turnId)).first();
    if (done) {
      await ctx.db.patch(thread._id, { pending, status: pending > 0 ? "thinking" : "idle" });
      return done.actions ?? [];
    }
    const made = await executeActions(ctx, userId, { turnId, ...(screen !== undefined ? { screen } : {}), ...(openSessionId !== undefined ? { openSessionId } : {}), ...(rev !== undefined ? { rev } : {}) }, actions);
    const { results } = made;
    // The trace of the turn gets what each action did, so a bad turn can be read back (ADR-027, ADR-032).
    const calls = await ctx.db.query("aiCalls").withIndex("by_user_and_job", (q) => q.eq("userId", userId).eq("job", "coach_turn")).order("desc").take(20);
    const call = calls.find((c) => c.ref === turnId);
    if (call) await ctx.db.patch(call._id, { actions: results });
    let proposal = made.proposal;
    let questionText = question?.text;
    if (plainLog && !proposal) {
      const content = await logThreadContent(ctx, userId, threadId);
      proposal = plainLogDraft(content.text, content.fileIds.length, now);
      questionText = "Save this as a plain note?";
    }
    if (plainPart && !proposal) {
      const said = (await messageByMessageId(ctx, userId, turnId))?.text.trim() ?? "";
      if (said) {
        proposal = { type: "log", kind: plainPart === "goal" ? "Goal" : "Note", summary: said.slice(0, 120), at: now, noEntry: true, plain: true, ...(plainPart === "goal" ? { goal: goalFromText(said) } : { note: { text: said.slice(0, 300), topic: "general" } }) };
        questionText = undefined;
      }
    }
    // A proposal always carries its two fixed answers; the model's own answers are dropped (ADR-032).
    const asked = proposal ? (proposal.type === "log" ? logQuestion(questionText) : proposalQuestion(questionText)) : question;
    const messageId = crypto.randomUUID();
    const messageDocId = await ctx.db.insert("messages", { userId, messageId, threadId, role: "assistant", text: message, fileIds: [], sources, turnId, actions: results, ...(asked ? { question: asked } : {}), ...(proposal ? { proposal } : {}), createdAt: now });
    // propose_program: the proposal is started with this message (the program card shows under it); the job build_program writes it (ADR-026).
    if (made.program) await startProgramProposal(ctx, userId, thread, messageDocId, messageId, made.program.brief, now, made.program.programId);
    await ctx.db.patch(thread._id, { pending, status: pending > 0 ? "thinking" : "idle", error: undefined, updatedAt: now, lastMessage: truncate(message, 200) });
    return results;
  },
});

/**
 * A newer user message of the thread gets its own coach turn, which answers this one too (ADR-040): this turn stays silent and gives its pending count back.
 * True when the turn was skipped.
 */
export const supersede = internalMutation({
  args: { userId: v.string(), threadId: v.string(), messageId: v.string() },
  handler: async (ctx, { userId, threadId, messageId }): Promise<boolean> => {
    const trigger = await messageByMessageId(ctx, userId, messageId);
    const thread = await threadByThreadId(ctx, userId, threadId);
    if (!trigger || !thread || trigger.role !== "user" || !(await hasNewerUserMessage(ctx, userId, threadId, trigger))) return false;
    const pending = Math.max(0, thread.pending - 1);
    await ctx.db.patch(thread._id, { pending, status: pending > 0 ? "thinking" : "idle" });
    return true;
  },
});

/** The coach_turn job: input -> AI pipeline (JSON, zod, one retry, fallback with no action) -> save. Any unexpected error fails the reply. */
export const run = internalAction({
  args: { userId: v.string(), threadId: v.string(), messageId: v.string() },
  handler: async (ctx, { userId, threadId, messageId }): Promise<void> => {
    if (await ctx.runMutation(internal.jobs.coachTurn.supersede, { userId, threadId, messageId })) return;
    const data = await ctx.runQuery(internal.jobs.coachTurn.input, { userId, threadId, messageId });
    if (!data) return;
    try {
      const provider = await providerFor(ctx, userId);
      const supportsImages = !!provider?.supportsImages;
      const isLog = data.turn.screen === "log";
      const plainPart = data.turn.screen === "goal" ? ("goal" as const) : data.turn.screen === "note" ? ("note" as const) : undefined;
      if (isLog && data.log?.photosOnly && !supportsImages) {
        // Only photos and none can be read: a fixed message, and Done still saves a plain note.
        await ctx.runMutation(internal.jobs.coachTurn.save, { userId, threadId, ...data.base, message: LOG_NO_PHOTO, actions: [], sources: [], plainLog: true });
        await ctx.scheduler.runAfter(0, internal.jobs.chat.summarise, { userId, threadId });
        return;
      }
      const files: AttachedFile[] = [];
      for (const f of data.chat.files) {
        const a = await loadAttachment(ctx, f, supportsImages);
        if (a) files.push(a);
      }
      const coach = assembleCoachContext(data.chat.data, files, supportsImages, await loadEntryImages(ctx, data.chat.entryImages, supportsImages));
      const r = await runAiJob(ctx, userId, coachTurnJob, { contextBlock: coach.contextBlock, history: data.chat.history, images: coach.images, turn: data.turn, limits: data.chat.data.limits }, { ref: messageId });
      await ctx.runMutation(internal.jobs.coachTurn.save, {userId, 
        threadId,
        ...data.base,
        message: isLog && r.path !== "ai" ? (provider ? LOG_UNREAD : LOG_NO_AI) : plainPart && !provider ? plainPartNoAi(plainPart) : r.value.message,
        actions: r.path === "ai" ? r.value.actions : [],
        ...(isLog && r.path !== "ai" && !provider ? { plainLog: true } : {}),
        ...(plainPart && r.path !== "ai" && !provider ? { plainPart } : {}),
        ...(r.value.question ? { question: r.value.question } : {}),
        sources: r.path === "ai" ? coach.sources : [],
      });
    } catch (e) {
      console.error(`[coach_turn] failed: ${(e as Error).message}`);
      await ctx.runMutation(internal.jobs.chat.fail, { userId, threadId, error: `The coach could not answer: ${truncate((e as Error).message, 120)}` });
      return;
    }
    await ctx.scheduler.runAfter(0, internal.jobs.chat.summarise, { userId, threadId });
  },
});
