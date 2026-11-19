import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { runAiJob } from "../lib/ai";
import { PROGRAM_BUILD_BUDGET_MS } from "../lib/constants";
import { allGoals, allSessions } from "../lib/db";
import { activeLimits } from "../lib/limitsDb";
import { allPlaces } from "../lib/placesDb";
import { programValue } from "../lib/programFields";
import { programByProgramId, programValueOf, proposalByProposalId } from "../lib/programsDb";
import { type BuildProgramInput, buildProgramJob } from "../model/ai/jobs/buildProgram";
import { coachPicture } from "../model/ai/jobs/coachPicture";
import { localDate } from "../model/program";

/** The most exercises of the log that go to the model. */
const KNOWN_EXERCISES_MAX = 60;

/** Bounded model input for one program proposal, or null when it is gone or no longer `building`. Never reads records (ADR-015). */
export const input = internalQuery({
  args: { proposalId: v.string() },
  handler: async (ctx, { proposalId }): Promise<BuildProgramInput | null> => {
    const doc = await proposalByProposalId(ctx, proposalId);
    if (!doc || doc.status !== "building") return null;
    const now = Date.now();
    const limits = await activeLimits(ctx);
    const goals = (await allGoals(ctx)).filter((g) => g.status === "active").sort((a, b) => a.createdAt - b.createdAt);
    // The picture of the user is the same one the session coach reads; only the parts a program needs are kept.
    const picture = coachPicture(await allSessions(ctx), goals, [], limits, [], now);
    const prev = doc.ask.previousProposalId ? await proposalByProposalId(ctx, doc.ask.previousProposalId) : null;
    const program = doc.target.id !== undefined ? await programByProgramId(ctx, doc.target.id) : null;
    return {
      today: `${localDate(now)} (${new Date(now).toLocaleDateString("en-GB", { weekday: "long", timeZone: process.env.APP_TIMEZONE || "UTC" })})`,
      request: doc.ask.text ?? "",
      ...(doc.ask.feedback ? { feedbackFromThePerson: doc.ask.feedback, ...(prev?.value ? { previousProgram: prev.value } : {}) } : {}),
      ...(program ? { currentProgram: programValueOf(program) } : {}),
      goalsInOrderOfPriority: picture.goalsInOrderOfPriority,
      limits,
      placesTheCoachKnows: (await allPlaces(ctx)).map((p) => ({ name: p.name, equipment: p.text })),
      exercisesTheUserKnows: picture.exercisesTheUserKnows.slice(0, KNOWN_EXERCISES_MAX).map((e) => ({ name: e.name, lastSets: e.lastSets, bestKg: e.bestKg })),
    };
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
