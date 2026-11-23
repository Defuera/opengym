import { localTime } from "./ai/jobs/shared";
import type { Entry } from "./schema";

/** One entry as the coach reads it: the date, the time and the user's own words. Photos and files are only counted. */
export interface CoachEntry {
  date: string;
  time: string;
  text: string;
  attachments: number;
  /** What the reader job saw in the photos or files of the entry, one line (ADR-031). An AI reading, not the user's words. */
  attachmentsShow?: string;
}

/** An entry with the reader job's one line about its photos or files, when there is one. */
export type CoachSourceEntry = Entry & { seen?: string };

/** The user's entries as plain data for a prompt. The caller bounds and orders the list (oldest first). */
export const entriesForPrompt = (entries: CoachSourceEntry[]): CoachEntry[] =>
  entries.map((e) => ({ date: new Date(e.at).toISOString().slice(0, 10), time: localTime(e.at), text: e.text, attachments: e.fileIds.length, ...(e.seen ? { attachmentsShow: e.seen } : {}) }));
