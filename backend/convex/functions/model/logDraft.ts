import { z } from "zod";
import { cut } from "./actionDetail";
import { formatSets } from "./proposalText";
import { ContextInputSchema, GoalInputSchema, ImportSessionDraftSchema, LimitSchema, type ContextInput, type GoalInput, type ImportSessionDraft, type PlanExercise } from "./schema";

/**
 * The log draft (ADR-032): the coach's reading of what the person logs in the log chat. Nothing is written until the person presses Done.
 * Pure: the executor (lib/logDraftDb.ts) reads the data and writes the rows.
 */

/** The category of the log: a short label chosen by the coach and tidied in code (model/entryCategory.ts). */
export type LogKind = string;

/** A limit as the coach drafts it: the existing limit shape, with no id (the server makes it). */
export const LimitDraftSchema = LimitSchema.omit({ limitId: true });
export type LimitDraft = z.infer<typeof LimitDraftSchema>;

const IsoMoment = z.string().trim().refine((s) => !Number.isNaN(Date.parse(s)), { message: "at must be an ISO date-time" });

const EditId = z.string().trim().min(1).max(100);

/** Which existing row a part of the draft changes (a goal, a limit or a note) instead of adding a new one. Never a delete: AI deletes nothing. */
export const DraftEditsSchema = z.object({ goalId: EditId.optional(), limitId: EditId.optional(), noteId: EditId.optional() });
export type DraftEdits = z.infer<typeof DraftEditsSchema>;

export const DraftLogArgs = z.object({
  /** The category. Needed in the log chat; any other chat has no entry and so no category. */
  kind: z.string().trim().min(1).max(60).optional(),
  /** The colour for a new category, "#RRGGBB". Ignored for a category that exists. */
  color: z.string().trim().max(20).nullish(),
  summary: z.string().trim().min(1).max(120),
  at: IsoMoment.optional(),
  session: ImportSessionDraftSchema.optional(),
  goal: GoalInputSchema.optional(),
  limit: LimitDraftSchema.optional(),
  note: ContextInputSchema.optional(),
  edits: DraftEditsSchema.optional(),
});
export type DraftLogArgs = z.infer<typeof DraftLogArgs>;

/** The draft as stored on the assistant message. `at` is in ms. */
export interface StoredLogDraft {
  type: "log";
  kind: LogKind;
  /** The category colour (#RRGGBB), from the stored category. */
  color?: string;
  summary: string;
  at: number;
  session?: ImportSessionDraft;
  goal?: GoalInput;
  limit?: LimitDraft;
  note?: ContextInput;
  /** Parts that change an existing goal, limit or note (by id) instead of adding one. */
  edits?: DraftEdits;
  /** Made outside the log chat: Done writes the parts only, no log entry (ADR-032, step D). Absent on drafts stored before step D: they make an entry. */
  noEntry?: boolean;
  plain?: boolean;
  appliedAt?: number;
  entryId?: string;
}

/** The two fixed answers of a log draft. The server sets them, whatever the model returned. */
export const LOG_ANSWERS = [
  { id: "approve", label: "Done" },
  { id: "change", label: "Add or change" },
] as const;
export const LOG_ANSWER_LABELS = new Set(LOG_ANSWERS.map((a) => a.label.toLowerCase()));
export const LOG_DEFAULT_QUESTION = "Is this right?";
export const logQuestion = (text?: string) => ({ text: text?.trim() || LOG_DEFAULT_QUESTION, answers: LOG_ANSWERS.map((a) => ({ ...a })) });

export const LOG_NO_PHOTO = "I cannot read photos right now. Add a few words about it, or press Done to save it as a plain note.";
export const LOG_NO_AI = "The coach is not available right now. Press Done to save what you wrote as a plain note, or add more.";
export const LOG_UNREAD = "I could not make a log of this just now, so nothing is drafted. Say it again, or add a few words.";

/** The reply when the goal or note chat has no AI answer: code drafts the person's words as they are. */
export const plainPartNoAi = (part: "goal" | "note") => `The coach is not available right now. Press Done to save your words as a ${part}, or add more.`;

/** The draft code makes when no AI answer is possible: a plain note of kind "other". Summary from the person's first words. */
export function plainLogDraft(text: string, files: number, now: number): StoredLogDraft {
  const first = text.trim().split("\n")[0]?.trim() ?? "";
  return { type: "log", kind: "other", summary: first ? cut(first).slice(0, 120) : files > 0 ? "Photo" : "Note", at: now, plain: true };
}

/** One line of what the draft holds, for the action result (max 120). */
export function logDetail(d: StoredLogDraft, dropped?: string): string {
  const e = d.edits ?? {};
  const parts = [d.session ? "session" : "", d.goal ? (e.goalId ? "goal change" : "goal") : "", d.limit ? (e.limitId ? "limit change" : "limit") : "", d.note ? (e.noteId ? "note change" : "note") : ""].filter(Boolean);
  return cut(d.noEntry ? `Drafted: ${parts.join(", ")}${dropped ? `. ${dropped}` : ""}` : `Drafted a log (${d.kind}${parts.length ? `: ${parts.join(", ")}` : ""})${dropped ? `. ${dropped}` : ""}`);
}

const day = (at: number, now: number): string => {
  const days = Math.round((Date.UTC(...ymd(now)) - Date.UTC(...ymd(at))) / 86_400_000);
  return days === 0 ? "" : days === 1 ? "yesterday" : new Date(at).toISOString().slice(0, 10);
};
const ymd = (ms: number): [number, number, number] => {
  const d = new Date(ms);
  return [d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()];
};

/** What Done wrote for one part: added, changed an existing one, or nothing. */
export type Wrote = "added" | "changed" | false;

/** The fixed reply to Done, built by code from what was written: "Logged: dinner, pasta. Session added." Without an entry: "Goal added." Pure. */
export function logDoneText(d: StoredLogDraft, wrote: { session: boolean; goal: Wrote; limit: Wrote; note: Wrote }, now: number): string {
  const word = (name: string, w: Wrote) => (w === "added" ? `${name} added.` : w === "changed" ? `${name} changed.` : "");
  const extra = [wrote.session ? "Session added." : "", word("Goal", wrote.goal), word("Limit", wrote.limit), word("Note", wrote.note)].filter(Boolean);
  if (d.noEntry) return extra.length > 0 ? extra.join(" ") : "Nothing was changed: what it would change is gone.";
  const when = day(d.at, now);
  const base = d.summary.trim().replace(/[.\s]+$/, "");
  const withDay = when && !base.toLowerCase().includes(when) ? `${base}, ${when}` : base;
  return [`Logged: ${withDay}.`, ...extra].join(" ");
}

export interface LogView {
  type: "log";
  kind: LogKind;
  /** The category colour (#RRGGBB) from the stored category. */
  color?: string;
  summary: string;
  at: number;
  session?: { type: string; focus?: string; minutes?: number; distanceKm?: number; exercises: { name: string; sets: string }[] };
  goal?: GoalInput;
  limit?: LimitDraft;
  note?: ContextInput;
  /** Which existing goal, limit or note a part changes. */
  edits?: DraftEdits;
  /** True when Done writes the parts only, with no log entry. */
  noEntry?: boolean;
  state: "open" | "applied" | "stale";
  entryId?: string;
}

/** The draft for the app. `sets` is a short text, as in a session proposal. */
export function logView(d: StoredLogDraft, state: LogView["state"]): LogView {
  const s = d.session;
  return {
    type: "log",
    kind: d.kind,
    ...(d.color ? { color: d.color } : {}),
    summary: d.summary,
    at: d.at,
    ...(s
      ? {
          session: {
            type: s.type,
            ...(s.focus ? { focus: s.focus } : {}),
            ...(s.minutes !== undefined ? { minutes: s.minutes } : {}),
            ...(s.distanceKm !== undefined ? { distanceKm: s.distanceKm } : {}),
            exercises: s.exercises.map((e) => ({ name: e.name, sets: formatSets(e as PlanExercise) })),
          },
        }
      : {}),
    ...(d.goal ? { goal: d.goal } : {}),
    ...(d.limit ? { limit: d.limit } : {}),
    ...(d.note ? { note: d.note } : {}),
    ...(d.edits ? { edits: d.edits } : {}),
    ...(d.noEntry ? { noEntry: true } : {}),
    state,
    ...(d.entryId ? { entryId: d.entryId } : {}),
  };
}

/** What a thread holds for one log: the person's words joined by a blank line, and every file, in order. */
export function logContent(messages: { role: string; text: string; fileIds: string[]; voice?: string; answered?: boolean }[]): { text: string; fileIds: string[] } {
  const mine = messages.filter((m) => m.role === "user" && m.voice !== "pending" && m.voice !== "failed" && !(m.answered && (!m.text.trim() || LOG_ANSWER_LABELS.has(m.text.trim().toLowerCase()))));
  const text = mine.map((m) => m.text).filter((t) => t.trim()).join("\n\n");
  return { text, fileIds: [...new Set(mine.flatMap((m) => m.fileIds))] };
}
