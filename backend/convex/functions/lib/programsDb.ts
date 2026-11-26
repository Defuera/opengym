import type { Doc } from "../_generated/dataModel";
import type { DatabaseReader } from "../_generated/server";
import type { ProgramValue } from "../model/schema";

type Reader = { db: DatabaseReader };

/**
 * The row of a program, MARKED OR NOT. Only code that must see a marked row uses this (commands/programs, jobs/purge).
 * Every other read uses `programByProgramId` or `liveProgramDocs`.
 */
export const programRowByProgramId = (ctx: Reader, userId: string, programId: string) =>
  ctx.db.query("programs").withIndex("by_user_and_programId", (q) => q.eq("userId", userId).eq("programId", programId)).unique();

/** The live program (not marked as deleted, ADR-020), or null. */
export async function programByProgramId(ctx: Reader, userId: string, programId: string): Promise<Doc<"programs"> | null> {
  const d = await programRowByProgramId(ctx, userId, programId);
  return d && d.deletedAt === undefined ? d : null;
}

/** Every live program, newest first. There are few, so one read is fine. */
export async function liveProgramDocs(ctx: Reader, userId: string): Promise<Doc<"programs">[]> {
  const docs = await ctx.db.query("programs").withIndex("by_user_and_deletedAt", (q) => q.eq("userId", userId).eq("deletedAt", undefined)).collect();
  return docs.sort((a, b) => b.createdAt - a.createdAt);
}

export const proposalByProposalId = (ctx: Reader, userId: string, proposalId: string) =>
  ctx.db.query("proposals").withIndex("by_user_and_proposalId", (q) => q.eq("userId", userId).eq("proposalId", proposalId)).unique();

/** A stored program as a program VALUE (the shape the coach proposes): the tests are plain texts again. */
export function programValueOf(d: Doc<"programs">): ProgramValue {
  return { title: d.title, purpose: d.purpose, startsOn: d.startsOn, endsOn: d.endsOn, week: d.week, phases: d.phases, rules: d.rules, tests: d.tests.map((t) => t.text) };
}

/**
 * True when a `ready` change proposal can no longer be applied: its program was deleted or changed after the proposal was made.
 * `accept` cannot store "stale" itself (a thrown mutation rolls its writes back), so the reads work it out here.
 */
export async function isStale(ctx: Reader, userId: string, d: Doc<"proposals">): Promise<boolean> {
  if (d.status !== "ready" || d.target.id === undefined) return false;
  const program = await programByProgramId(ctx, userId, d.target.id);
  return !program || program.rev !== d.base;
}

/** What the app reads of a proposal (queries/proposals:get and :open). `stale` says the change proposal is out of date (see isStale). */
export function proposalView(d: Doc<"proposals">, stale = false) {
  return {
    proposalId: d.proposalId,
    target: d.target,
    status: stale ? ("stale" as const) : d.status,
    approval: d.approval,
    origin: d.origin,
    value: d.value ?? null,
    reason: d.reason ?? null,
    source: d.source ?? null,
    error: d.error ?? null,
  };
}
