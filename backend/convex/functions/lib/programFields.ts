import { v } from "convex/values";
import { planExercise } from "./validators";

/** One session of a program phase, written out in full. `key` is what the program `week` lists ("A", "B", "Bike"). */
export const programSession = v.object({
  key: v.string(),
  title: v.string(),
  activity: v.string(),
  exercises: v.array(planExercise),
  note: v.optional(v.string()),
});

/** A phase: the weeks it covers (inclusive) and the sessions as they are done in those weeks. */
export const programPhase = v.object({
  title: v.string(),
  weekFrom: v.number(),
  weekTo: v.number(),
  note: v.string(),
  sessions: v.array(programSession),
});

/** What the coach proposes and what the person agrees to: the whole program, as plain data. Tests are plain texts here. */
export const programValue = v.object({
  title: v.string(),
  purpose: v.string(),
  startsOn: v.string(),
  endsOn: v.string(),
  /** The session keys of ONE week, in order. A key may repeat (A, B, A). */
  week: v.array(v.string()),
  phases: v.array(programPhase),
  rules: v.array(v.string()),
  tests: v.array(v.string()),
});

export const programStatus = v.union(v.literal("active"), v.literal("paused"), v.literal("done"));

/** A test of a stored program: its text, and the day it was done (set by a later step; kept when the text stays). */
export const programTest = v.object({ testId: v.string(), text: v.string(), doneOn: v.optional(v.string()) });

/** A program the person agreed to. Not an AI product any more: it is the person's own plan (the AI only proposes). */
export const programFields = {
  programId: v.string(),
  title: v.string(),
  purpose: v.string(),
  startsOn: v.string(),
  endsOn: v.string(),
  week: v.array(v.string()),
  phases: v.array(programPhase),
  rules: v.array(v.string()),
  tests: v.array(programTest),
  status: programStatus,
  /** The text the person pasted or typed when it was first proposed. */
  sourceText: v.optional(v.string()),
  /** +1 on every change. A change proposal is only applied while the program still has the rev it was made on. */
  rev: v.number(),
  createdAt: v.number(),
  updatedAt: v.number(),
  /** Set by commands/programs:remove. Same rule as `sessions.deletedAt` (ADR-020): invisible to every read, erased by jobs/purge. */
  deletedAt: v.optional(v.number()),
};

/** What a proposal is about. A union of one now; later kinds (a limit, a goal) join it. No `id` = a new thing. */
export const proposalTarget = v.union(v.object({ kind: v.literal("program"), id: v.optional(v.string()) }));
export const proposalKind = v.literal("program");
/** What a thread is about (ADR-026). A union of one now. No `id` = a new program that does not exist yet; it is set when the proposal is agreed. */
export const threadAbout = v.object({ kind: v.literal("program"), id: v.optional(v.string()) });
export const proposalApproval = v.union(v.literal("none"), v.literal("explicit"));
export const proposalOrigin = v.union(v.literal("request"), v.literal("feedback"), v.literal("chat"));
export const proposalStatus = v.union(v.literal("building"), v.literal("ready"), v.literal("applied"), v.literal("declined"), v.literal("stale"), v.literal("failed"));

/** The shared frame of "the coach proposes, the person agrees". `value` is the proposed thing (a program value for kind program). */
export const proposalFields = {
  proposalId: v.string(),
  target: proposalTarget,
  value: v.optional(programValue),
  reason: v.optional(v.string()),
  /** The target's `rev` when the proposal was made. Only with `target.id`. */
  base: v.optional(v.number()),
  approval: proposalApproval,
  origin: proposalOrigin,
  status: proposalStatus,
  source: v.optional(v.union(v.literal("ai"), v.literal("rules"))),
  ask: v.object({ text: v.optional(v.string()), feedback: v.optional(v.array(v.string())), previousProposalId: v.optional(v.string()) }),
  error: v.optional(v.string()),
  /** The chat thread and the assistant message this proposal came from (origin `chat`, ADR-026). */
  threadId: v.optional(v.string()),
  messageId: v.optional(v.string()),
  createdAt: v.number(),
  decidedAt: v.optional(v.number()),
};
