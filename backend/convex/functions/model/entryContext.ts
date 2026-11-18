import { localTime } from "./ai/jobs/shared";
import type { Entry } from "./schema";

/** One entry as the coach reads it: the date, the time and the user's own words. Photos and files are only counted. */
export interface CoachEntry {
  date: string;
  time: string;
  text: string;
  attachments: number;
}

/** The user's entries as plain data for a prompt. The caller bounds and orders the list (oldest first). */
export const entriesForPrompt = (entries: Entry[]): CoachEntry[] =>
  entries.map((e) => ({ date: new Date(e.at).toISOString().slice(0, 10), time: localTime(e.at), text: e.text, attachments: e.fileIds.length }));
