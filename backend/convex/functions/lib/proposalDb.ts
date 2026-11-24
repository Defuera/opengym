import type { Doc } from "../_generated/dataModel";
import type { MutationCtx, QueryCtx } from "../_generated/server";
import { allSessions } from "./db";
import { activeLimits } from "./limitsDb";
import { rebuiltPlan } from "../model/openSession";
import { toPlanned } from "../model/coachTools";
import { finalizePlan } from "../model/proposals";

/** The two quick answers of a proposal. The server sets them itself, whatever the model returned (ADR-032). */
export const PROPOSAL_ANSWERS = [
  { id: "approve", label: "Approve" },
  { id: "change", label: "Change something" },
] as const;

export const PROPOSAL_DONE = "Done. The session is rebuilt.";
export const PROPOSAL_DEFAULT_QUESTION = "Do you approve this plan?";

/** The question a message with a proposal carries: the model's text when it gave one, and always the two fixed answers. */
export const proposalQuestion = (text?: string) => ({ text: text?.trim() || PROPOSAL_DEFAULT_QUESTION, answers: PROPOSAL_ANSWERS.map((a) => ({ ...a })) });

type Reader = QueryCtx | MutationCtx;

/** Why a stored proposal cannot be applied (a newer proposal in the thread, no open session, another session), or null. */
export async function staleReason(ctx: Reader, message: Doc<"messages">): Promise<string | null> {
  const p = message.proposal;
  if (!p) return "there is no proposal";
  const newer = await ctx.db
    .query("messages")
    .withIndex("by_threadId", (q) => q.eq("threadId", message.threadId).gt("_creationTime", message._creationTime))
    .filter((q) => q.neq(q.field("proposal"), undefined))
    .first();
  if (newer) return "a newer proposal came after it";
  const row = await ctx.db.query("openSession").first();
  if (!row) return "no session is open now";
  if (row.id !== p.openSessionId) return "another session is open now";
  return null;
}

export type ApplyOutcome = { status: "applied" | "already" | "refused"; text: string; reason?: string };

/**
 * Applies the stored proposal of an assistant message in plain code, with no AI call: the plan safety limits and avoid rules are
 * checked again, then the same merge as every outside plan (the person's done sets and comments stay at the front, ADR-028/029).
 * Writes the open session once (`rev + 1`, `updatedBy: "coach"`) and marks the proposal applied. A second call changes nothing.
 */
export async function applyProposal(ctx: MutationCtx, message: Doc<"messages">): Promise<ApplyOutcome> {
  const p = message.proposal;
  if (!p) return { status: "refused", text: "There is no plan to apply.", reason: "there is no proposal" };
  if (p.appliedAt !== undefined) return { status: "already", text: "This plan was applied already. Nothing more changed." };
  const stale = await staleReason(ctx, message);
  const refuse = (reason: string): ApplyOutcome => ({ status: "refused", text: `I could not apply this plan: ${reason}. Nothing was changed. Ask me again if you still want it.`, reason });
  if (stale) return refuse(stale);
  const row = (await ctx.db.query("openSession").first())!;
  const list = finalizePlan({ rationale: "", exercises: p.exercises }, await allSessions(ctx), await activeLimits(ctx)).exercises;
  if (list.length === 0) return refuse("no exercise is left after the limits");
  const stamp = Date.now().toString(36);
  let n = 0;
  const next = rebuiltPlan(row.exercises, list.map(toPlanned), () => `${stamp}p${(n++).toString(36)}`, p.focus, p.planNote);
  await ctx.db.patch(row._id, { exercises: next.exercises, ...(next.focus !== undefined ? { focus: next.focus } : {}), ...(next.planNote !== undefined ? { planNote: next.planNote } : {}), rev: row.rev + 1, updatedAt: Date.now(), updatedBy: "coach" });
  await ctx.db.patch(message._id, { proposal: { ...p, appliedAt: Date.now() } });
  return { status: "applied", text: PROPOSAL_DONE };
}
