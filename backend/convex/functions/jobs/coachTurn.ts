import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { providerFor, runAiJob } from "../lib/ai";
import { allSessions, entryByEntryId, messageByMessageId, threadByThreadId } from "../lib/db";
import { readChatInput } from "../lib/chatInputDb";
import { executeActions } from "../lib/coachToolsDb";
import { proposalQuestion } from "../lib/proposalDb";
import { loadEntryImages } from "../lib/entriesDb";
import { loadAttachment } from "../lib/files";
import { coachQuestion } from "../lib/messageFields";
import { allPlaces } from "../lib/placesDb";
import { liveProgramDocs } from "../lib/programsDb";
import { coachTurnJob } from "../model/ai/jobs/coachTurn";
import { type AttachedFile, assembleCoachContext } from "../model/coachContext";
import { turnScreen } from "../model/coachTurnInput";
import { localDate } from "../model/program";
import { programsForCoach } from "../model/programForCoach";
import { truncate } from "../model/rules/util";

/**
 * The coach turn (ADR-032): one chat answer with functions. Scheduled by commands/messages:send for a message sent from the session
 * or an exercise. Input: what a chat reply reads (lib/chatInputDb.ts) plus the screen, read by the server now: the open session
 * with exercise ids, done flags and rev, the exercise in view, the session's place and every place, the entry and the programs.
 */
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
    const turn = {
      ...screen,
      ...(entry ? { entryInView: { entryId: entry.entryId, text: entry.text, at: new Date(entry.at).toISOString(), files: entry.fileIds.length } } : {}),
      ...(programs.length > 0 ? { programsThePersonFollows: programs } : {}),
      ...(trigger.fileIds.length > 0 ? { attachedToThisMessage: chat.files.filter((f) => trigger.fileIds.includes(f.fileId)).map((f) => f.name) } : {}),
    };
    return { chat, turn, base: { turnId: messageId, ...(row ? { openSessionId: row.id, rev: row.rev } : {}) } };
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
  },
  handler: async (ctx, { threadId, turnId, openSessionId, rev, message, actions, question, sources }) => {
    const thread = await threadByThreadId(ctx, threadId);
    if (!thread) return null;
    const now = Date.now();
    const pending = Math.max(0, thread.pending - 1);
    const done = await ctx.db.query("messages").withIndex("by_turnId", (q) => q.eq("turnId", turnId)).first();
    if (done) {
      await ctx.db.patch(thread._id, { pending, status: pending > 0 ? "thinking" : "idle" });
      return done.actions ?? [];
    }
    const { results, proposal } = await executeActions(ctx, { turnId, ...(openSessionId !== undefined ? { openSessionId } : {}), ...(rev !== undefined ? { rev } : {}) }, actions);
    // A proposal always carries the two fixed answers; the model's own answers are dropped (ADR-032).
    const asked = proposal ? proposalQuestion(question?.text) : question;
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
      const supportsImages = !!(await providerFor(ctx))?.supportsImages;
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
        message: r.value.message,
        actions: r.path === "ai" ? r.value.actions : [],
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
