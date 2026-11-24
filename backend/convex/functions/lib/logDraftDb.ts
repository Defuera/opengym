import type { Doc } from "../_generated/dataModel";
import type { MutationCtx, QueryCtx } from "../_generated/server";
import { allSessions, contextByItemId, fromSession, goalByGoalId } from "./db";
import { knownCategories } from "./categoriesDb";
import { ensureCategory } from "./categoriesDb";
import { storeEntry } from "./entriesDb";
import { markFactsChanged, scheduleReview } from "./factsChanged";
import { fileByFileId } from "./files";
import { limitByLimitId } from "./limitsDb";
import { writeImportItems } from "./importWrite";
import { finalizeLogExercises, usualSets } from "../model/ai/jobs/parseLog";
import { finalizeGoalExercise, mergeRules } from "../model/goalDraft";
import { normaliseCategory } from "../model/entryCategory";
import { draftToSession } from "../model/importUnits";
import { type DraftLogArgs, type StoredLogDraft, type Wrote, logContent, logDoneText } from "../model/logDraft";
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

type DraftExercise = ImportSessionDraft["exercises"][number];

/** An exercise the person named with no sets: the usual sets of the log when it is there, else the exercise with no sets. */
function withUsualSets(e: DraftExercise, usual: Parameters<typeof finalizeLogExercises>[1]): DraftExercise[] {
  const [filled] = finalizeLogExercises([{ name: e.name, measure: e.measure === "time" ? ("time" as const) : undefined, sets: undefined }], usual);
  return [filled ? (filled as unknown as DraftExercise) : (e.measure === "time" ? { name: e.name, measure: "time", sets: [] } : { name: e.name, sets: [] })];
}

/**
 * Checks the draft_log arguments again against the data (the zod shape passed already) and makes the stored draft.
 * `at`: the moment the log is about; an unreadable or far-future one becomes now. A gym session: an exercise with no sets takes the usual
 * sets of the log, or stays in the session with no sets (never dropped, never made up); the session is dropped only when it does not validate, and then the action says so.
 * A goal keeps its exercise only when it is a name of the log (as the old goal reading did). An edit names an existing goal, limit or note; one that is gone drops that part.
 * A part that cannot be written is dropped and `dropped` says why; the rest of the draft stays.
 * `inLog` is true in the log chat: the draft has a category and Done writes a log entry. Anywhere else (ADR-032, step D) only a goal, a limit
 * and a note are drafted, with no entry and no category; a draft with none of them is rejected (`reject`), and the coach tells the person to use the Log.
 */
export async function buildLogDraft(ctx: MutationCtx, a: DraftLogArgs, now: number, inLog = true): Promise<{ draft: StoredLogDraft; dropped?: string } | { reject: string }> {
  if (inLog && !a.kind) return { reject: "the category (kind) is needed in the log chat" };
  const given = a.at ? Date.parse(a.at) : NaN;
  const at = Number.isNaN(given) || given > now + FUTURE_SLACK_MS ? now : Math.max(0, Math.round(given));
  const drops: string[] = [];
  const edits: NonNullable<StoredLogDraft["edits"]> = {};
  let goal = a.goal;
  let limit = a.limit;
  let note = a.note;
  if (goal && a.edits?.goalId) {
    if (await goalByGoalId(ctx, a.edits.goalId)) edits.goalId = a.edits.goalId;
    else (goal = undefined), drops.push("The goal to change is gone.");
  }
  if (limit && a.edits?.limitId) {
    if (await limitByLimitId(ctx, a.edits.limitId)) edits.limitId = a.edits.limitId;
    else (limit = undefined), drops.push("The limit to change is gone.");
  }
  if (note && a.edits?.noteId) {
    if (await contextByItemId(ctx, a.edits.noteId)) edits.noteId = a.edits.noteId;
    else (note = undefined), drops.push("The note to change is gone.");
  }
  if (!inLog && !goal && !limit && !note) return { reject: drops[0] ?? "outside the log chat only a goal, a limit or a note can be drafted: tell the person to use Log for this" };
  const base = { type: "log" as const, at, summary: a.summary, ...(Object.keys(edits).length > 0 ? { edits } : {}), ...(inLog ? {} : { noEntry: true }) };
  let draft: StoredLogDraft;
  if (inLog) {
    const kind = normaliseCategory(a.kind!, (await knownCategories(ctx)).map((c) => c.label));
    const category = await ensureCategory(ctx, kind, a.color, "ai");
    draft = { ...base, kind: category?.label ?? kind, ...(category ? { color: category.color } : {}) };
  } else {
    draft = { ...base, kind: goal ? "Goal" : limit ? "Limit" : "Note" };
  }
  if (a.session && inLog) {
    const s = a.session;
    const usual = usualSets(await allSessions(ctx));
    // An exercise with no sets takes its usual sets; when the log has none it is KEPT with no sets (the person's word, never invented sets).
    const exercises = s.kind === "gym" ? s.exercises.flatMap((e) => (e.sets.length > 0 ? [e] : withUsualSets(e, usual))) : [];
    const candidate: ImportSessionDraft = { ...s, exercises, date: new Date(at).toISOString() };
    const ok = draftToSession(candidate, { name: "log", createdAt: at }, "check", () => "check", new Set());
    if (ok) draft.session = candidate;
    else drops.push("The session was left out: it did not validate.");
  } else if (a.session) drops.push("The session was left out: log it in the Log chat.");
  if (goal) {
    const names = [...new Set((await allSessions(ctx)).flatMap((s) => s.exercises.map((e) => e.name)))];
    draft.goal = finalizeGoalExercise(goal, names);
  }
  if (limit) draft.limit = limit;
  if (note) draft.note = note;
  return { draft, ...(drops.length > 0 ? { dropped: drops.join(" ") } : {}) };
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
 * "Done" on a draft, in plain code with no AI call, in one transaction, once (ADR-032). In the log chat it writes ONE entry through the same logic as
 * commands/entries:save: the person's messages of the thread up to the draft, joined by a blank line, unchanged, with all their files, at the draft's
 * time and with the label set from the draft (the reader job does not run). Then, each only when the draft holds it: a session (as an import writes
 * it, `importId` = the entry id, then the facts-changed and review scheduling of a save), a goal, a limit, a note, tagged with the entry id. The entry
 * keeps which rows it made (`read.made`). The proposal becomes applied. A second call changes nothing. Ids come from the entry id, so a repeat is safe.
 * A draft made outside the log chat (`noEntry`, step D) writes the parts only. A part with `edits` changes that goal, limit or note (the draft is the whole
 * new value; the rules of a limit keep their stored exercises, its records and check-ins stay); when that row is gone now, the part is skipped and the reply says so.
 */
export async function applyLogDraft(ctx: MutationCtx, message: Doc<"messages">): Promise<LogOutcome> {
  const p = message.proposal;
  if (!p || p.type !== "log") return { status: "refused", text: "There is nothing to log.", reason: "there is no log draft" };
  const draft = p as StoredLogDraft;
  if (draft.appliedAt !== undefined) return { status: "already", text: draft.noEntry ? "This was saved already. Nothing more changed." : "This was logged already. Nothing more changed.", ...(draft.entryId ? { entryId: draft.entryId } : {}) };
  const stale = await staleReason(ctx, message);
  if (stale || message.turnId === undefined) return { status: "refused", text: `I could not log this: ${stale ?? "the draft has no turn"}. Nothing was changed. Say it again if you still want it.`, reason: stale ?? "the draft has no turn" };
  const now = Date.now();
  const entryId = `l-${message.turnId}`;
  const made: { sessionId?: string; goalId?: string; limitId?: string; contextId?: string } = {};
  const wrote: { session: boolean; goal: Wrote; limit: Wrote; note: Wrote } = { session: false, goal: false, limit: false, note: false };
  const edits = draft.edits ?? {};

  if (draft.session) {
    const session = draftToSession({ ...draft.session, date: new Date(draft.at).toISOString() }, { name: "log", createdAt: draft.at }, entryId, () => `${entryId}-s`, new Set());
    if (session) {
      await writeImportItems(ctx, { sessions: [fromSession(session)] });
      made.sessionId = session.id;
    }
  }
  if (draft.goal) {
    const old = edits.goalId ? await goalByGoalId(ctx, edits.goalId) : null;
    const g = draft.goal;
    if (old) {
      // A change of an existing goal: the same structure fields as a new one; title and fields the draft leaves out are cleared (the draft is the whole goal).
      await ctx.db.patch(old._id, { title: g.title, kind: g.kind, exercise: g.exercise, targetKg: g.targetKg, sessionsPerWeek: g.sessionsPerWeek });
      wrote.goal = "changed";
    } else if (!edits.goalId && !(await goalByGoalId(ctx, `${entryId}-g`))) {
      await ctx.db.insert("goals", { goalId: `${entryId}-g`, ...g, status: "active", source: "ai", threadId: message.threadId, importId: entryId, createdAt: now });
      made.goalId = `${entryId}-g`;
      wrote.goal = "added";
    }
  }
  if (draft.limit) {
    const old = edits.limitId ? await limitByLimitId(ctx, edits.limitId) : null;
    const l = draft.limit;
    if (old) {
      await ctx.db.patch(old._id, { title: l.title, status: l.status, since: l.since ?? old.since, rules: mergeRules(old.rules, l.rules) });
      wrote.limit = "changed";
    } else if (!edits.limitId && !(await limitByLimitId(ctx, `${entryId}-l`))) {
      await ctx.db.insert("limits", { limitId: `${entryId}-l`, ...l, importId: entryId });
      made.limitId = `${entryId}-l`;
      wrote.limit = "added";
    }
  }
  if (draft.note) {
    const old = edits.noteId ? await contextByItemId(ctx, edits.noteId) : null;
    if (old) {
      await ctx.db.patch(old._id, { text: draft.note.text, topic: draft.note.topic });
      wrote.note = "changed";
    } else if (!edits.noteId && !(await contextByItemId(ctx, `${entryId}-n`))) {
      await ctx.db.insert("context", { itemId: `${entryId}-n`, ...draft.note, active: true, source: "ai", threadId: message.threadId, importId: entryId, createdAt: now });
      made.contextId = `${entryId}-n`;
      wrote.note = "added";
    }
  }
  wrote.session = made.sessionId !== undefined;
  let storedEntry: string | undefined;
  if (!draft.noEntry) {
    // The log chat: ONE entry from the person's words and files, unchanged, labelled from the draft (the reader job does not run).
    const content = await logThreadContent(ctx, message.threadId, message._creationTime);
    const fileIds: string[] = [];
    for (const id of content.fileIds) if (fileIds.length < ENTRY_FILES_MAX && (await fileByFileId(ctx, id))) fileIds.push(id);
    const text = content.text.slice(0, ENTRY_TEXT_MAX);
    await storeEntry(ctx, { entryId, text: text.trim() || fileIds.length > 0 ? text : draft.summary, fileIds, at: draft.at, createdAt: now }, { kind: draft.kind, summary: draft.summary, ...(Object.keys(made).length > 0 ? { made } : {}) });
    storedEntry = entryId;
  }
  if (wrote.session || wrote.goal || wrote.limit || wrote.note) await markFactsChanged(ctx);
  if (made.sessionId !== undefined) await scheduleReview(ctx, made.sessionId);
  await ctx.db.patch(message._id, { proposal: { ...p, appliedAt: now, ...(storedEntry ? { entryId: storedEntry } : {}) } });
  const out = logDoneText(draft, wrote, now);
  return { status: "applied", text: out, ...(storedEntry ? { entryId: storedEntry } : {}) };
}
