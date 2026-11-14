import type { ImageInput } from "../provider";
import type { JobDef } from "../run-job";
import { dataPrompt, systemPrompt } from "../prompt-rules";
import { type ImportOutput, ImportOutputSchema } from "../../schema";

export interface ImportInput {
  fileName: string;
  /** ISO date of upload, used by the model only as a hint; code applies the default. */
  uploadedAt: string;
  chunk?: string;
  chunkIndex: number;
  chunkCount: number;
  image?: ImageInput;
}

export const IMPORT_NEEDS_AI_NOTE = "AI is required to import data; nothing was imported.";

export const importDataJob: JobDef<ImportInput, ImportOutput> = {
  name: "import_data",
  description: "Maps a text chunk (log export, notes, csv, pdf text) or a photo (for example a cycling machine screen) to sessions, goals and context items.",
  fallbackDescription: "Nothing is imported; the job note says AI is required.",
  json: true,
  maxTokens: 3000,
  output: ImportOutputSchema as import("zod").ZodType<ImportOutput>,
  build: (i) => ({
    system: systemPrompt(
      "import_data",
      "Extract training records from the supplied text or photo. Only record what is visible; never invent sessions, sets or dates. Gym sessions list exercises with sets; cardio or machine readouts become kind 'activity' with minutes and distanceKm and no exercises. Give 'date' as ISO (YYYY-MM-DD or full timestamp) only if the source shows one, otherwise omit it. Goals only for explicit targets. Context items for notes about preferences or limits, stated in training terms. Use 'notes' for anything unclear.",
      `{"sessions": [{"kind": "gym" | "activity", "type": string (max 40; e.g. Push, Cycle), "date"?: string, "exercises": [{"name": string, "sets": [{"reps": int, "kg": number, "max"?: boolean}]}], "minutes"?: int, "distanceKm"?: number, "note"?: string}], "goals": [{"title": string, "kind": "strength"|"consistency"|"work_around"|"custom", "exercise"?: string, "targetKg"?: number, "sessionsPerWeek"?: int}], "context": [{"text": string, "topic": string}], "notes": string[]}`,
    ),
    messages: [
      {
        role: "user",
        content: dataPrompt(`File ${i.fileName}, part ${i.chunkIndex + 1} of ${i.chunkCount}.`, { fileName: i.fileName, uploadedAt: i.uploadedAt, hasImage: !!i.image, text: i.chunk ?? null }),
      },
    ],
    images: i.image ? [i.image] : undefined,
  }),
  fallback: () => ({ sessions: [], goals: [], context: [], notes: [IMPORT_NEEDS_AI_NOTE] }),
};
