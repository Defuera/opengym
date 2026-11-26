import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { providerFor, runAiJob } from "../lib/ai";
import { userTimezone } from "../lib/timezoneDb";
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
  args: { userId: v.string(), proposalId: v.string() },
  handler: async (ctx, { userId, proposalId }): Promise<BuildProgramInput | null> => {
    const doc = await proposalByProposalId(ctx, userId, proposalId);
    if (!doc || doc.status !== "building") return null;
    const now = Date.now();
    const tz = await userTimezone(ctx, userId);
    const limits = await limitsForAi(ctx, userId);
    const goals = (await allGoals(ctx, userId)).filter((g) => g.status === "active").sort((a, b) => a.createdAt - b.createdAt);
    // The picture of the user is the same one the session coach reads; only the parts a program needs are kept.
    const picture = coachPicture(await allSessions(ctx, userId), goals, [], limits, [], now, undefined, tz);
    const prev = doc.ask.previousProposalId ? await proposalByProposalId(ctx, userId, doc.ask.previousProposalId) : null;
    const program = doc.target.id !== undefined ? await programByProgramId(ctx, userId, doc.target.id) : null;
    return {
      today: todayLabel(now, tz),
      request: doc.ask.text ?? "",
      ...(doc.ask.feedback ? { feedbackFromThePerson: doc.ask.feedback, ...(prev?.value ? { previousProgram: prev.value } : {}) } : {}),
      ...(program ? { currentProgram: programValueOf(program) } : {}),
      goalsInOrderOfPriority: picture.goalsInOrderOfPriority,
      limits,
      placesTheCoachKnows: (await allPlaces(ctx, userId)).map((p) => ({ name: p.name, equipment: p.text, knowledge: knowledgeOf(p) })),
      exercisesTheUserKnows: picture.exercisesTheUserKnows.slice(0, KNOWN_EXERCISES_MAX).map((e) => ({ name: e.name, lastSets: e.lastSets, bestKg: e.bestKg })),
    };
  },
});

/** The files of the thread a proposal came from (newest 6 of the person's messages, not audio); none when it has no thread (ADR-026). */
export const threadFiles = internalQuery({
  args: { userId: v.string(), proposalId: v.string() },
  handler: async (ctx, { userId, proposalId }) => {
    const doc = await proposalByProposalId(ctx, userId, proposalId);
    return doc?.threadId !== undefined ? await threadUserFiles(ctx, userId, doc.threadId) : [];
  },
});

/**
 * Stores the result: `ready` with the value and the reason, or `failed` with a short error. Only a `building` proposal is changed, so a late or
 * repeated job (or one the person cancelled meanwhile) changes nothing.
 */
export const save = internalMutation({
  args: { userId: v.string(), proposalId: v.string(), value: v.optional(programValue), reason: v.optional(v.string()), error: v.optional(v.string()) },
  handler: async (ctx, { userId, proposalId, value, reason, error }) => {
    const doc = await proposalByProposalId(ctx, userId, proposalId);
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
  args: { userId: v.string(), proposalId: v.string() },
  handler: async (ctx, { userId, proposalId }): Promise<void> => {
    try {
      const job = await ctx.runQuery(internal.jobs.programs.input, { userId, proposalId });
      if (!job) return;
      // A proposal made in a chat reads the files of that chat (a photo or a text of a program), as the chat reply does.
      const files = await ctx.runQuery(internal.jobs.programs.threadFiles, { userId, proposalId });
      if (files.length) {
        const supportsImages = !!(await providerFor(ctx, userId))?.supportsImages;
        const loaded = [];
        for (const f of files) {
          const a = await loadAttachment(ctx, f, supportsImages);
          if (a) loaded.push(a);
        }
        Object.assign(job, attachmentsForPrompt(loaded, supportsImages));
      }
      const r = await runAiJob(ctx, userId, buildProgramJob, job, { timeoutMs: PROGRAM_BUILD_BUDGET_MS });
      if (r.path !== "ai") {
        await ctx.runMutation(internal.jobs.programs.save, { userId, proposalId, error: `The coach could not write the program (${r.reason ?? "no answer"}).` });
        return;
      }
      const { reason, ...value } = r.value;
      await ctx.runMutation(internal.jobs.programs.save, { userId, proposalId, value, reason });
    } catch (e) {
      console.error(`[program] build failed: ${(e as Error).message.slice(0, 200)}`);
      await ctx.runMutation(internal.jobs.programs.save, { userId, proposalId, error: "The coach could not write the program." });
    }
  },
});
