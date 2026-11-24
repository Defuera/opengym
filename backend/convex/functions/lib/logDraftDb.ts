import type { Doc } from "../_generated/dataModel";
import type { MutationCtx, QueryCtx } from "../_generated/server";
import { allSessions, contextByItemId, fromSession, goalByGoalId } from "./db";
import { storeEntry } from "./entriesDb";
import { markFactsChanged, scheduleReview } from "./factsChanged";
import { fileByFileId } from "./files";
import { limitByLimitId } from "./limitsDb";
import { writeImportItems } from "./importWrite";
import { finalizeLogExercises, usualSets } from "../model/ai/jobs/parseLog";
import { draftToSession } from "../model/importUnits";
import { type DraftLogArgs, type StoredLogDraft, logContent, logDoneText } from "../model/logDraft";
import type { ImportSessionDraft } from "../model/schema";

type Reader = Pick<QueryCtx, "db">;

/** The entry text of the schema allows 2000 characters and 10 files. */
const ENTRY_TEXT_MAX = 2000;
const ENTRY_FILES_MAX = 10;
const FUTURE_SLACK_MS = 3_600_000;

/** The person's messages of a thread up to a point (`_creationTime`, inclusive), oldest first. */
export async function logThreadMessages(ctx: Reader, threadId: string, upTo?: number): Promise<Doc<"messages">[]> {
  const rows = await ctx.db.query("messages").withIndex("by_threadId", (q) => q.eq("threadId", threadId)).order("asc").collect();
  return rows.filter((m) => m.role === "user" && (upTo === undefined || m._creationTime <= upTo));
}

/** What the log of this thread holds up to a point: the words joined by a blank line, and every file. */
export async function logThreadContent(ctx: Reader, threadId: string, upTo?: number) {
  return logContent((await logThreadMessages(ctx, threadId, upTo)).map((m) => ({ role: m.role, text: m.text, fileIds: m.fileIds, ...(m.voice ? { voice: m.voice } : {}), answered: m.answer !== undefined })));
}

/**
 * Checks the draft_log arguments again against the data (the zod shape passed already) and makes the stored draft.
 * `at`: the moment the log is about; an unreadable or far-future one becomes now. A gym session: an exercise with no sets takes the usual
 * sets of the log, or is left out ("reported without sets = the usual sets", as parse_log does); the model never makes sets up here.
 * A part that cannot be written is dropped and `dropped` says why; the rest of the draft stays.
 */
export async function buildLogDraft(ctx: Reader, a: DraftLogArgs, now: number): Promise<{ draft: StoredLogDraft; dropped?: string }> {
  const given = a.at ? Date.parse(a.at) : NaN;
  const at = Number.isNaN(given) || given > now + FUTURE_SLACK_MS ? now : Math.max(0, Math.round(given));
  const draft: StoredLogDraft = { type: "log", kind: a.kind, summary: a.summary, at };
  let dropped: string | undefined;
  if (a.session) {
    const s = a.session;
    const usual = usualSets(await allSessions(ctx));
    const exercises = s.kind === "gym" ? s.exercises.flatMap((e) => (e.sets.length > 0 ? [e] : (finalizeLogExercises([{ name: e.name, measure: e.measure === "time" ? ("time" as const) : undefined, sets: undefined }], usual) as unknown as ImportSessionDraft["exercises"]))) : [];
    const candidate: ImportSessionDraft = { ...s, exercises, date: new Date(at).toISOString() };
    const ok = (s.kind === "activity" || exercises.length > 0) && draftToSession(candidate, { name: "log", createdAt: at }, "check", () => "check", new Set());
    if (ok) draft.session = candidate;
    else dropped = "The session was left out: no exercise with sets is known.";
  }
  if (a.goal) draft.goal = a.goal;
  if (a.limit) draft.limit = a.limit;
  if (a.note) draft.note = a.note;
  return { draft, ...(dropped ? { dropped } : {}) };
}

export type LogOutcome = { status: "applied" | "already" | "refused"; text: string; reason?: string; entryId?: string };

/** Why a stored log draft cannot be applied: a newer proposal came after it in the thread. */
async function staleReason(ctx: Reader, message: Doc<"messages">): Promise<string | null> {
  const newer = await ctx.db
    .query("messages")
    .withIndex("by_threadId", (q) => q.eq("threadId", message.threadId).gt("_creationTime", message._creationTime))
    .filter((q) => q.neq(q.field("proposal"), undefined))
    .first();
  return newer ? "a newer draft came after it" : null;
}

/**
 * "Done" on a log draft, in plain code with no AI call, in one transaction, once (ADR-032). Writes ONE entry through the same logic as
 * commands/entries:save: the person's messages of the thread up to the draft, joined by a blank line, unchanged, with all their files, at the draft's
 * time and with the label set from the draft (the reader job does not run). Then, each only when the draft holds it: a session (as an import writes
 * it, `importId` = the entry id, then the facts-changed and review scheduling of a save), a goal, a limit, a note, tagged with the entry id. The entry
 * keeps which rows it made (`read.made`). The proposal becomes applied. A second call changes nothing. Ids come from the entry id, so a repeat is safe.
 */
export async function applyLogDraft(ctx: MutationCtx, message: Doc<"messages">): Promise<LogOutcome> {
  const p = message.proposal;
  if (!p || p.type !== "log") return { status: "refused", text: "There is nothing to log.", reason: "there is no log draft" };
  const draft = p as StoredLogDraft;
  if (draft.appliedAt !== undefined) return { status: "already", text: "This was logged already. Nothing more changed.", ...(draft.entryId ? { entryId: draft.entryId } : {}) };
  const stale = await staleReason(ctx, message);
  if (stale || message.turnId === undefined) return { status: "refused", text: `I could not log this: ${stale ?? "the draft has no turn"}. Nothing was changed. Say it again if you still want it.`, reason: stale ?? "the draft has no turn" };
  const now = Date.now();
  const entryId = `l-${message.turnId}`;
  const content = await logThreadContent(ctx, message.threadId, message._creationTime);
  const fileIds: string[] = [];
  for (const id of content.fileIds) if (fileIds.length < ENTRY_FILES_MAX && (await fileByFileId(ctx, id))) fileIds.push(id);
  const text = content.text.slice(0, ENTRY_TEXT_MAX);
  const made: { sessionId?: string; goalId?: string; limitId?: string; contextId?: string } = {};

  if (draft.session) {
    const session = draftToSession({ ...draft.session, date: new Date(draft.at).toISOString() }, { name: "log", createdAt: draft.at }, entryId, () => `${entryId}-s`, new Set());
    if (session) {
      await writeImportItems(ctx, { sessions: [fromSession(session)] });
      made.sessionId = session.id;
    }
  }
  if (draft.goal && !(await goalByGoalId(ctx, `${entryId}-g`))) {
    await ctx.db.insert("goals", { goalId: `${entryId}-g`, ...draft.goal, status: "active", source: "ai", threadId: message.threadId, importId: entryId, createdAt: now });
    made.goalId = `${entryId}-g`;
  }
  if (draft.limit && !(await limitByLimitId(ctx, `${entryId}-l`))) {
    await ctx.db.insert("limits", { limitId: `${entryId}-l`, ...draft.limit, importId: entryId });
    made.limitId = `${entryId}-l`;
  }
  if (draft.note && !(await contextByItemId(ctx, `${entryId}-n`))) {
    await ctx.db.insert("context", { itemId: `${entryId}-n`, ...draft.note, active: true, source: "ai", threadId: message.threadId, importId: entryId, createdAt: now });
    made.contextId = `${entryId}-n`;
  }
  await storeEntry(ctx, { entryId, text: text.trim() || fileIds.length > 0 ? text : draft.summary, fileIds, at: draft.at, createdAt: now }, { kind: draft.kind, summary: draft.summary, ...(Object.keys(made).length > 0 ? { made } : {}) });
  if (Object.keys(made).length > 0) await markFactsChanged(ctx);
  if (made.sessionId !== undefined) await scheduleReview(ctx, made.sessionId);
  await ctx.db.patch(message._id, { proposal: { ...p, appliedAt: now, entryId } });
  const out = logDoneText(draft, { session: made.sessionId !== undefined, goal: made.goalId !== undefined, limit: made.limitId !== undefined, note: made.contextId !== undefined }, now);
  return { status: "applied", text: out, entryId };
}
