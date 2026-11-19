import { ConvexError, v } from "convex/values";
import { internal } from "../_generated/api";
import { mutation } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { PROPOSAL_FEEDBACK_KEEP, PROPOSAL_FEEDBACK_MAX, PROPOSAL_PURGE_BATCH, PROPOSAL_TEXT_MAX, PROPOSAL_TTL_MS } from "../lib/constants";
import { threadByThreadId } from "../lib/db";
import { markFactsChanged } from "../lib/factsChanged";
import { activeLimits } from "../lib/limitsDb";
import { programByProgramId, proposalByProposalId } from "../lib/programsDb";
import { proposalKind } from "../lib/programFields";
import { checkProgramValue } from "../model/program";
import { approvalFor } from "../model/proposalPolicy";

const clip = (id: string, what: string): string => {
  const t = id.trim();
  if (t.length < 1 || t.length > 100) throw new ConvexError(`${what} must be 1..100 characters`);
  return t;
};

/**
 * Asks the coach for a proposal (today: a program). Idempotent by the client-made `proposalId`: a resend changes and schedules nothing.
 * Two forms. A NEW ASK has `text` (1..8000): a pasted program or a wish. A REBUILD has `feedback` (1..1000) and `previousProposalId`:
 * the new row copies the target and the ask text of the previous row (which must exist and be `ready`), keeps its feedback rounds
 * (at most 5, oldest dropped) and the previous row becomes `declined`. With a rebuild a given `text` or `targetId` is ignored: the
 * previous row decides. With `targetId` a new ask is a CHANGE of that program (it must exist; `base` = its rev now).
 * Inserts status `building` and schedules jobs/programs:build. `approval` and `origin` are set here from model/proposalPolicy.ts,
 * never by the client. Proposals older than 7 days are removed here, as startRequests are in commands/start:request.
 * Returns the proposalId.
 */
export const request = mutation({
  args: {
    token: v.string(),
    proposalId: v.string(),
    kind: proposalKind,
    targetId: v.optional(v.string()),
    text: v.optional(v.string()),
    feedback: v.optional(v.string()),
    previousProposalId: v.optional(v.string()),
  },
  handler: async (ctx, { token, proposalId, kind, targetId, text, feedback, previousProposalId }): Promise<string> => {
    requireToken(token);
    const id = clip(proposalId, "proposalId");
    if ((feedback === undefined) !== (previousProposalId === undefined)) throw new ConvexError("feedback and previousProposalId go together");
    const rebuild = feedback !== undefined;
    const cleanFeedback = feedback?.trim();
    if (cleanFeedback !== undefined && (cleanFeedback.length < 1 || cleanFeedback.length > PROPOSAL_FEEDBACK_MAX)) throw new ConvexError(`feedback must be 1..${PROPOSAL_FEEDBACK_MAX} characters`);
    const prevId = previousProposalId === undefined ? undefined : clip(previousProposalId, "previousProposalId");
    const cleanText = text?.trim();
    if (!rebuild && (cleanText === undefined || cleanText.length < 1 || cleanText.length > PROPOSAL_TEXT_MAX)) throw new ConvexError(`text must be 1..${PROPOSAL_TEXT_MAX} characters`);
    const cleanTarget = targetId === undefined ? undefined : clip(targetId, "targetId");
    const now = Date.now();
    const old = await ctx.db.query("proposals").withIndex("by_createdAt", (q) => q.lt("createdAt", now - PROPOSAL_TTL_MS)).take(PROPOSAL_PURGE_BATCH);
    for (const d of old) await ctx.db.delete(d._id);
    if (await proposalByProposalId(ctx, id)) return id;
    const prev = rebuild ? await proposalByProposalId(ctx, prevId!) : null;
    if (rebuild && !prev) throw new ConvexError("previous proposal not found (it may be older than 7 days)");
    if (prev && prev.status !== "ready") throw new ConvexError("previous proposal is not ready");
    const target = prev ? prev.target : { kind, ...(cleanTarget !== undefined ? { id: cleanTarget } : {}) };
    // A change: the program must exist now. Its rev is what the proposal is made on (accept checks it again).
    let base: number | undefined;
    if (target.id !== undefined) {
      const program = await programByProgramId(ctx, target.id);
      if (!program) throw new ConvexError("program not found");
      base = program.rev;
    }
    const origin = rebuild ? "feedback" : "request";
    const askText = prev ? prev.ask.text : cleanText;
    await ctx.db.insert("proposals", {
      proposalId: id,
      target,
      ...(base !== undefined ? { base } : {}),
      approval: approvalFor(kind, origin),
      origin,
      status: "building",
      ask: {
        ...(askText !== undefined ? { text: askText } : {}),
        ...(prev ? { feedback: [...(prev.ask.feedback ?? []), cleanFeedback!].slice(-PROPOSAL_FEEDBACK_KEEP), previousProposalId: prev.proposalId } : {}),
      },
      createdAt: now,
    });
    if (prev) await ctx.db.patch(prev._id, { status: "declined", decidedAt: now });
    await ctx.scheduler.runAfter(0, internal.jobs.programs.build, { proposalId: id });
    return id;
  },
});

/**
 * The person agrees: applies a `ready` proposal. The value is checked again with the limits of this moment (a limit may have changed
 * since it was proposed); the reason is thrown as it is. A new program is inserted `active`, rev 1, with the ask text as `sourceText`
 * and tests with fresh ids. A change needs the program to exist with `rev === base`; else this throws "The program changed. Ask again."
 * (a thrown mutation keeps no write, so the row stays `ready`; queries/proposals reports it as `stale`, see lib/programsDb isStale) The change replaces the value and keeps programId, status, createdAt and the done day of a test
 * whose text did not change; rev + 1. When the proposal came from a chat thread (`threadId`) whose `about.id` is not set, the thread is now about the
 * program (`about.id`) and an automatic title becomes the program title. Returns { programId }.
 */
export const accept = mutation({
  args: { token: v.string(), proposalId: v.string() },
  handler: async (ctx, { token, proposalId }): Promise<{ programId: string }> => {
    requireToken(token);
    const p = await proposalByProposalId(ctx, proposalId);
    if (!p) throw new ConvexError("proposal not found");
    if (p.status !== "ready" || !p.value) throw new ConvexError("This proposal is not ready.");
    const bad = checkProgramValue(p.value, await activeLimits(ctx));
    if (bad) throw new ConvexError(bad);
    const now = Date.now();
    const { tests, ...value } = p.value;
    let programId: string;
    if (p.target.id === undefined) {
      programId = p.proposalId;
      await ctx.db.insert("programs", {
        programId,
        ...value,
        tests: tests.map((text, i) => ({ testId: `${programId}-t${i + 1}`, text })),
        status: "active",
        ...(p.ask.text !== undefined ? { sourceText: p.ask.text } : {}),
        rev: 1,
        createdAt: now,
        updatedAt: now,
      });
    } else {
      programId = p.target.id;
      const program = await programByProgramId(ctx, programId);
      if (!program || program.rev !== p.base) throw new ConvexError("The program changed. Ask again.");
      const rev = program.rev + 1;
      await ctx.db.patch(program._id, {
        ...value,
        tests: tests.map((text, i) => {
          const same = program.tests.find((t) => t.text === text);
          return { testId: same?.testId ?? `${programId}-t${rev}-${i + 1}`, text, ...(same?.doneOn !== undefined ? { doneOn: same.doneOn } : {}) };
        }),
        rev,
        updatedAt: now,
      });
    }
    await ctx.db.patch(p._id, { status: "applied", decidedAt: now });
    // A chat about a new program becomes the chat about this program (ADR-026); an unnamed thread takes the program's title.
    const thread = p.threadId !== undefined ? await threadByThreadId(ctx, p.threadId) : null;
    if (thread?.about && thread.about.id === undefined) await ctx.db.patch(thread._id, { about: { ...thread.about, id: programId }, ...(thread.titleSource === "auto" ? { title: value.title } : {}) });
    await markFactsChanged(ctx);
    return { programId };
  },
});

/** The person says no: a `building` or `ready` proposal becomes `declined`. Any other status is left as it is. Returns null. */
export const decline = mutation({
  args: { token: v.string(), proposalId: v.string() },
  handler: async (ctx, { token, proposalId }): Promise<null> => {
    requireToken(token);
    const p = await proposalByProposalId(ctx, proposalId);
    if (p && (p.status === "building" || p.status === "ready")) await ctx.db.patch(p._id, { status: "declined", decidedAt: Date.now() });
    return null;
  },
});
