import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalQuery } from "../_generated/server";
import { providerFor, runAiJob } from "../lib/ai";
import { threadByThreadId } from "../lib/db";
import { loadEntryImages } from "../lib/entriesDb";
import { loadAttachment } from "../lib/files";
import { todayLabel } from "../lib/programChatDb";
import { programByProgramId, programValueOf } from "../lib/programsDb";
import { chatProgramJob } from "../model/ai/jobs/chatProgram";
import { assembleCoachContext, type AttachedFile } from "../model/coachContext";
import { truncate } from "../model/rules/util";

/** What the coach of a program thread knows besides the chat context: the program, the proposal the person looks at, whether one is being written. */
export const context = internalQuery({
  args: { threadId: v.string() },
  handler: async (ctx, { threadId }) => {
    const thread = await threadByThreadId(ctx, threadId);
    const program = thread?.about?.id !== undefined ? await programByProgramId(ctx, thread.about.id) : null;
    const mine = await ctx.db.query("proposals").withIndex("by_threadId", (q) => q.eq("threadId", threadId)).collect();
    const open = mine.filter((p) => p.status === "ready" && p.value).sort((a, b) => b.createdAt - a.createdAt)[0];
    return {
      today: todayLabel(Date.now()),
      ...(program ? { currentProgram: programValueOf(program) } : {}),
      ...(open?.value ? { openProposal: open.value } : {}),
      proposalBeingWritten: mine.some((p) => p.status === "building"),
    };
  },
});

/**
 * The coach reply in a thread about a program (ADR-026), run by jobs/chat:reply. Same steps as a normal reply (bounded context, files,
 * the job, store the message, summarise_thread), with the chat_program job. `title_thread` and `extract_from_chat` do not run: the program holds
 * what the person said, and nothing is written silently from a pasted program. When the job sets `proposeProgram`, jobs/chat:saveReply starts the proposal.
 */
export const reply = internalAction({
  args: { threadId: v.string(), messageId: v.string() },
  handler: async (ctx, { threadId, messageId }): Promise<void> => {
    const data = await ctx.runQuery(internal.jobs.chat.input, { threadId, messageId });
    if (!data) return;
    try {
      const supportsImages = !!(await providerFor(ctx))?.supportsImages;
      const files: AttachedFile[] = [];
      for (const f of data.files) {
        const a = await loadAttachment(ctx, f, supportsImages);
        if (a) files.push(a);
      }
      const coach = assembleCoachContext(data.data, files, supportsImages, await loadEntryImages(ctx, data.entryImages, supportsImages));
      const state = await ctx.runQuery(internal.jobs.programChat.context, { threadId });
      const r = await runAiJob(ctx, chatProgramJob, { contextBlock: coach.contextBlock, history: data.history, images: coach.images, ...state });
      const kept = await ctx.runMutation(internal.jobs.chat.saveReply, {
        threadId,
        text: r.value.text,
        sources: r.path === "ai" ? coach.sources : [],
        ...(r.path === "ai" && r.value.proposeProgram ? { proposeProgram: r.value.proposeProgram } : {}),
      });
      if (!kept) return;
    } catch (e) {
      console.error(`[chat] program reply failed: ${(e as Error).message}`);
      await ctx.runMutation(internal.jobs.chat.fail, { threadId, error: `The coach could not answer: ${truncate((e as Error).message, 120)}` });
      return;
    }
    await ctx.scheduler.runAfter(0, internal.jobs.chat.summarise, { threadId });
  },
});
