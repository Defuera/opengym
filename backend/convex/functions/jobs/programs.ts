import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { providerFor, runAiJob } from "../lib/ai";
import { PROGRAM_BUILD_BUDGET_MS } from "../lib/constants";
import { loadAttachment } from "../lib/files";
import { attachmentsForPrompt } from "../model/attachedFiles";
import { allGoals, allSessions } from "../lib/db";
import { limitsForAi } from "../lib/limitsDb";
import { knowledgeOf } from "../model/placeKnowledge";
import { allPlaces } from "../lib/placesDb";
import { threadUserFiles, todayLabel } from "../lib/programChatDb";
import { programValue } from "../lib/programFields";
import { programByProgramId, programValueOf, proposalByProposalId } from "../lib/programsDb";
import { type BuildProgramInput, buildProgramJob } from "../model/ai/jobs/buildProgram";
import { coachPicture } from "../model/ai/jobs/coachPicture";

/** The most exercises of the log that go to the model. */
const KNOWN_EXERCISES_MAX = 60;

/** Bounded model input for one program proposal, or null when it is gone or no longer `building`. Reads the limits with their records (ADR-033). */
export const input = internalQuery({
  args: { proposalId: v.string() },
  handler: async (ctx, { proposalId }): Promise<BuildProgramInput | null> => {
    const doc = await proposalByProposalId(ctx, proposalId);
    if (!doc || doc.status !== "building") return null;
    const now = Date.now();
    const limits = await limitsForAi(ctx);
    const goals = (await allGoals(ctx)).filter((g) => g.status === "active").sort((a, b) => a.createdAt - b.createdAt);
    // The picture of the user is the same one the session coach reads; only the parts a program needs are kept.
    const picture = coachPicture(await allSessions(ctx), goals, [], limits, [], now);
    const prev = doc.ask.previousProposalId ? await proposalByProposalId(ctx, doc.ask.previousProposalId) : null;
    const program = doc.target.id !== undefined ? await programByProgramId(ctx, doc.target.id) : null;
    return {
      today: todayLabel(now),
      request: doc.ask.text ?? "",
      ...(doc.ask.feedback ? { feedbackFromThePerson: doc.ask.feedback, ...(prev?.value ? { previousProgram: prev.value } : {}) } : {}),
      ...(program ? { currentProgram: programValueOf(program) } : {}),
      goalsInOrderOfPriority: picture.goalsInOrderOfPriority,
      limits,
      placesTheCoachKnows: (await allPlaces(ctx)).map((p) => ({ name: p.name, equipment: p.text, knowledge: knowledgeOf(p) })),
      exercisesTheUserKnows: picture.exercisesTheUserKnows.slice(0, KNOWN_EXERCISES_MAX).map((e) => ({ name: e.name, lastSets: e.lastSets, bestKg: e.bestKg })),
    };
  },
});

/** The files of the thread a proposal came from (newest 6 of the person's messages, not audio); none when it has no thread (ADR-026). */
export const threadFiles = internalQuery({
  args: { proposalId: v.string() },
  handler: async (ctx, { proposalId }) => {
    const doc = await proposalByProposalId(ctx, proposalId);
    return doc?.threadId !== undefined ? await threadUserFiles(ctx, doc.threadId) : [];
  },
});

/**
 * Stores the result: `ready` with the value and the reason, or `failed` with a short error. Only a `building` proposal is changed, so a late or
 * repeated job (or one the person cancelled meanwhile) changes nothing.
 */
export const save = internalMutation({
  args: { proposalId: v.string(), value: v.optional(programValue), reason: v.optional(v.string()), error: v.optional(v.string()) },
  handler: async (ctx, { proposalId, value, reason, error }) => {
    const doc = await proposalByProposalId(ctx, proposalId);
    if (!doc || doc.status !== "building") return;
    if (!value) {
      await ctx.db.patch(doc._id, { status: "failed", error: (error ?? "The coach could not make the program.").slice(0, 200), decidedAt: Date.now() });
      return;
    }
    await ctx.db.patch(doc._id, { status: "ready", value, source: "ai", ...(reason ? { reason: reason.slice(0, 200) } : {}) });
  },
});

/**
 * build_program job: input query -> AI pipeline (one retry) -> save. There is no rules fallback (a program cannot be made by rules): when the AI
 * fails the proposal is `failed` with a short error. Any unexpected error marks it failed too. Never throws.
 */
export const build = internalAction({
  args: { proposalId: v.string() },
  handler: async (ctx, { proposalId }): Promise<void> => {
    try {
      const job = await ctx.runQuery(internal.jobs.programs.input, { proposalId });
      if (!job) return;
      // A proposal made in a chat reads the files of that chat (a photo or a text of a program), as the chat reply does.
      const files = await ctx.runQuery(internal.jobs.programs.threadFiles, { proposalId });
      if (files.length) {
        const supportsImages = !!(await providerFor(ctx))?.supportsImages;
        const loaded = [];
        for (const f of files) {
          const a = await loadAttachment(ctx, f, supportsImages);
          if (a) loaded.push(a);
        }
        Object.assign(job, attachmentsForPrompt(loaded, supportsImages));
      }
      const r = await runAiJob(ctx, buildProgramJob, job, { timeoutMs: PROGRAM_BUILD_BUDGET_MS });
      if (r.path !== "ai") {
        await ctx.runMutation(internal.jobs.programs.save, { proposalId, error: `The coach could not write the program (${r.reason ?? "no answer"}).` });
        return;
      }
      const { reason, ...value } = r.value;
      await ctx.runMutation(internal.jobs.programs.save, { proposalId, value, reason });
    } catch (e) {
      console.error(`[program] build failed: ${(e as Error).message.slice(0, 200)}`);
      await ctx.runMutation(internal.jobs.programs.save, { proposalId, error: "The coach could not write the program." });
    }
  },
});
