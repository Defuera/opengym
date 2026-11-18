import { z } from "zod";
import type { JobDef } from "../runJob";
import { dataPrompt, systemPrompt } from "../promptRules";

/**
 * learn_place (ADR-021): reads one sentence the user said and keeps the note of what is at ONE place up to date.
 * Background only: it never blocks a reply. The code writes the note when `changed` is true and the text differs, and logs the quote.
 * ADR-004 pipeline: prompt, provider, JSON, zod, one retry, plain code fallback (no change).
 */
export interface LearnPlaceInput {
  /** The place the sentence is about: its name and the equipment note now ("" when nothing is known). */
  place: { name: string; equipment: string };
  /** The names of the other places the person has. */
  otherPlaces: string[];
  /** The user's own sentence (feedback on a plan, the note for today, or a chat message). */
  sentence: string;
}

export const LearnPlaceSchema = z.object({ changed: z.boolean(), equipment: z.string().max(1500) });
export type LearnPlaceOutput = z.infer<typeof LearnPlaceSchema>;

const ROLE = `You keep a short note about one place where a person trains. The note is a plain list of what is and what is not at this place. Change it only when the sentence says something about the equipment or the room of THIS place (not of another place in otherPlaces); never invent anything; otherwise set changed to false and return the note as it is.`;

export const learnPlaceJob: JobDef<LearnPlaceInput, LearnPlaceOutput> = {
  name: "learn_place",
  description: "Updates the equipment note of one place from one sentence the user said (feedback, the note for today, or a chat message about the place).",
  fallbackDescription: "No change: the note stays as it is.",
  json: true,
  maxTokens: 800,
  output: LearnPlaceSchema,
  build: (i) => ({
    system: systemPrompt("learn_place", ROLE, `{"changed": boolean, "equipment": string (the whole note after the change; max 1500 chars)}`),
    messages: [{ role: "user", content: dataPrompt("Update the note of this place if the sentence calls for it.", { place: i.place, otherPlaces: i.otherPlaces, sentence: i.sentence }) }],
  }),
  fallback: (i) => ({ changed: false, equipment: i.place.equipment.slice(0, 1500) }),
};
