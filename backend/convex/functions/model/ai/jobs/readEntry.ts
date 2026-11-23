import { z } from "zod";
import type { ImageInput } from "../provider";
import type { JobDef } from "../runJob";
import { dataPrompt, systemPrompt } from "../promptRules";

export const ENTRY_KINDS = ["meal", "training", "body", "goal", "other"] as const;

export interface ReadEntryInput {
  /** The user's own words. May be empty when a photo or a file is attached. */
  text: string;
  /** Local date and time the entry is about. */
  when: string;
  /** Text read from attached files that are not images. */
  files: { name: string; text: string }[];
  images: ImageInput[];
}

export const ReadEntryOutputSchema = z.object({
  kind: z.enum(ENTRY_KINDS),
  summary: z.string().trim().min(1).max(120),
});
export type ReadEntryOutput = z.infer<typeof ReadEntryOutputSchema>;

/**
 * read_entry (ADR-031): says what one log entry is, and gives one line about it. Step 1 of the general log entry: the label
 * only. It writes no session, goal or note.
 */
export const readEntryJob: JobDef<ReadEntryInput, ReadEntryOutput> = {
  name: "read_entry",
  description: "Reads one log entry (text, photos, files) and says what it is (meal, training, body, goal, other) with one line about it.",
  fallbackDescription: "No label: the entry shows as the user wrote it.",
  json: true,
  maxTokens: 400,
  output: ReadEntryOutputSchema,
  build: (i) => ({
    system: systemPrompt(
      "read_entry",
      [
        "The person logged one entry in a training app: words, photos, files, or a mix. Say what it is and give one line about it.",
        "kind: 'meal' for food or drink. 'training' for exercise the person did or a record of it (a workout in words, a machine screen, a tracker screenshot, an exported log). 'body' for how the body is: pain, an injury, something to avoid, sleep, tiredness, illness, weight or other body measures. 'goal' for something the person wants to reach. 'other' for everything else.",
        "summary: one line, at most 120 characters, in the language of the person's words (English when there are none). Say what is there, with the numbers that are visible: for a meal the foods, for training the activity with time, distance or main sets, for body the part and the state. Describe only what the words, photos and files show. Do not guess calories or weights that are not shown. Do not give advice. Do not repeat the kind as a label.",
        "When the words and a photo disagree, the words win.",
      ].join("\n"),
      `{"kind": "meal" | "training" | "body" | "goal" | "other", "summary": string (1..120)}`,
    ),
    messages: [{ role: "user", content: dataPrompt("Read this entry.", { when: i.when, text: i.text, photos: i.images.length, files: i.files }) }],
    images: i.images.length ? i.images : undefined,
  }),
  fallback: () => ({ kind: "other", summary: "Not read." }),
};
