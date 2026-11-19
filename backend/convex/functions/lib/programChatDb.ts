import { internal } from "../_generated/api";
import type { Doc } from "../_generated/dataModel";
import type { DatabaseReader, MutationCtx } from "../_generated/server";
import { PROPOSAL_FEEDBACK_KEEP, PROPOSAL_TEXT_MAX } from "./constants";
import { fileByFileId, type FileDoc } from "./files";
import { programByProgramId } from "./programsDb";
import { localDate } from "../model/program";
import { approvalFor } from "../model/proposalPolicy";

/** Today as the program jobs read it: "YYYY-MM-DD (Weekday)" in the owner's time zone. */
export const todayLabel = (now: number): string => `${localDate(now)} (${new Date(now).toLocaleDateString("en-GB", { weekday: "long", timeZone: process.env.APP_TIMEZONE || "UTC" })})`;

/** The most files of a thread that go to a program build. */
export const THREAD_FILES_MAX = 6;
/** Messages read to find the texts and the files of a thread. */
const THREAD_READ_MAX = 200;

/**
 * The request text of a program proposal made in a thread: the texts of the person's messages, oldest first, joined with a blank line,
 * cut from the START so the newest text stays, then the coach's brief. The whole text is at most PROPOSAL_TEXT_MAX characters.
 */
export async function requestText(ctx: { db: DatabaseReader }, threadId: string, brief: string): Promise<string> {
  const summary = `The coach's summary of what to write: ${brief}`;
  const budget = Math.max(0, PROPOSAL_TEXT_MAX - summary.length - 2);
  const recent = await ctx.db.query("messages").withIndex("by_threadId", (q) => q.eq("threadId", threadId)).order("desc").take(THREAD_READ_MAX);
  const texts = recent.filter((m) => m.role === "user" && m.text.trim()).map((m) => m.text.trim()).reverse();
  const said = budget > 0 ? texts.join("\n\n").slice(-budget).trim() : "";
  return said ? `${said}\n\n${summary}` : summary;
}

/**
 * The coach said "write the program now" in a thread about a program (ADR-026). In the caller's mutation: the thread's `building` and
 * `ready` proposals become `declined`; a new `building` proposal is inserted, linked to the thread and to the assistant message (which gets
 * its `proposalId`); jobs/programs:build is scheduled. The new proposal carries the newest `ready` proposal as `previousProposalId` and
 * the feedback rounds so far, so the build knows what the person saw. Does nothing when the thread's program is gone. Returns the proposalId.
 */
export async function startProgramProposal(ctx: MutationCtx, thread: Doc<"threads">, messageDocId: Doc<"messages">["_id"], messageId: string, brief: string, now: number): Promise<string | null> {
  const programId = thread.about?.id;
  const program = programId !== undefined ? await programByProgramId(ctx, programId) : null;
  if (programId !== undefined && !program) return null;
  const mine = await ctx.db.query("proposals").withIndex("by_threadId", (q) => q.eq("threadId", thread.threadId)).collect();
  const open = mine.filter((p) => p.status === "building" || p.status === "ready");
  const prev = open.filter((p) => p.status === "ready" && p.value).sort((a, b) => b.createdAt - a.createdAt)[0];
  for (const p of open) await ctx.db.patch(p._id, { status: "declined", decidedAt: now });
  const proposalId = crypto.randomUUID();
  await ctx.db.insert("proposals", {
    proposalId,
    target: { kind: "program", ...(programId !== undefined ? { id: programId } : {}) },
    ...(program ? { base: program.rev } : {}),
    approval: approvalFor("program", "chat"),
    origin: "chat",
    status: "building",
    threadId: thread.threadId,
    messageId,
    ask: {
      text: await requestText(ctx, thread.threadId, brief),
      ...(prev ? { feedback: [...(prev.ask.feedback ?? []), brief].slice(-PROPOSAL_FEEDBACK_KEEP), previousProposalId: prev.proposalId } : {}),
    },
    createdAt: now,
  });
  await ctx.db.patch(messageDocId, { proposalId });
  await ctx.scheduler.runAfter(0, internal.jobs.programs.build, { proposalId });
  return proposalId;
}

/** The files of a thread's user messages, newest 6 (not audio), oldest first. Same pick as the chat reply makes. */
export async function threadUserFiles(ctx: { db: DatabaseReader }, threadId: string): Promise<FileDoc[]> {
  const recent = await ctx.db.query("messages").withIndex("by_threadId", (q) => q.eq("threadId", threadId)).order("desc").take(THREAD_READ_MAX);
  const ids = [...new Set(recent.filter((m) => m.role === "user").flatMap((m) => [...(m.fileIds ?? [])].reverse()))];
  const out: FileDoc[] = [];
  for (const id of ids) {
    if (out.length >= THREAD_FILES_MAX) break;
    const f = await fileByFileId(ctx, id);
    if (f && f.kind !== "audio") out.push({ fileId: f.fileId, storageId: f.storageId, name: f.name, mime: f.mime, size: f.size, kind: f.kind, createdAt: f.createdAt });
  }
  return out.reverse();
}
