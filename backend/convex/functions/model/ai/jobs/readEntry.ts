import { z } from "zod";
import type { ImageInput } from "../provider";
import type { JobDef } from "../runJob";
import { COLOR_RULE } from "../../categoryColor";
import { dataPrompt, systemPrompt } from "../promptRules";

export interface ReadEntryInput {
  /** The user's own words. May be empty when a photo or a file is attached. */
  text: string;
  /** Local date and time the entry is about. */
  when: string;
  /** Text read from attached files that are not images. */
  files: { name: string; text: string }[];
  images: ImageInput[];
  /** The categories the person's entries use now, most used first. */
  categories?: { label: string; color?: string }[];
}

export const ReadEntryOutputSchema = z.object({
  kind: z.string().trim().min(1).max(60),
  color: z.string().trim().max(20).nullish(),
  summary: z.string().trim().min(1).max(120),
});
export type ReadEntryOutput = z.infer<typeof ReadEntryOutputSchema>;

/**
 * read_entry (ADR-031): says what one log entry is, and gives one line about it. Step 1 of the general log entry: the label
 * only. It writes no session, goal or note.
 */
export const readEntryJob: JobDef<ReadEntryInput, ReadEntryOutput> = {
  name: "read_entry",
  description: "Reads one log entry (text, photos, files) and gives it a short category label with one line about it.",
  fallbackDescription: "No label: the entry shows as the user wrote it.",
  json: true,
  maxTokens: 400,
  output: ReadEntryOutputSchema,
  build: (i) => ({
    system: systemPrompt(
      "read_entry",
      [
        "The person logged one entry in a training app: words, photos, files, or a mix. Say what it is and give one line about it.",
        "kind: the category of the entry: one or two words, Title case, in English (for example Meal, Training, Sleep, Body, Walk, Goal). Choose the category by what the entry is about. When one of categoriesInUse fits, use it exactly. Create a new category only when none of them fits. Use 'Note' when the entry has no clear subject. Do not put a date, a food name or a number in the category.",
        COLOR_RULE,
        "summary: one line, at most 120 characters, in the language of the person's words (English when there are none). Say what is there, with the numbers that are visible: for a meal the foods, for training the activity with time, distance or main sets, for body the part and the state. Describe only what the words, photos and files show. Do not guess calories or weights that are not shown. Do not give advice. Do not repeat the kind as a label.",
        "When the words and a photo disagree, the words win.",
      ].join("\n"),
      `{"kind": string (1..24, the category), "color"?: "#RRGGBB", "summary": string (1..120)}`,
    ),
    messages: [{ role: "user", content: dataPrompt("Read this entry.", { when: i.when, categoriesInUse: i.categories ?? [], text: i.text, photos: i.images.length, files: i.files }) }],
    images: i.images.length ? i.images : undefined,
  }),
  fallback: () => ({ kind: "other", summary: "Not read." }),
};
