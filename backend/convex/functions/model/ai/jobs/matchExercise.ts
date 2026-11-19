import { z } from "zod";
import type { JobDef } from "../runJob";
import { dataPrompt, systemPrompt } from "../promptRules";

/**
 * match_exercise: the person logs an exercise under their own name; pick the candidate from the public exercise list
 * that is the same movement on the same kind of equipment, or null. Only the exercise name and public list entries go to the provider.
 * ADR-004 pipeline: prompt, provider, JSON, zod, one retry, plain code fallback.
 */
export interface MatchExerciseInput {
  exercise: string;
  candidates: { id: string; name: string; equipment: string }[];
}

export const MatchExerciseSchema = z.object({ id: z.string().nullable(), movement: z.string().max(400).optional() });
export type MatchExerciseOutput = z.infer<typeof MatchExerciseSchema>;

const ROLE = `A person logs an exercise under their own name. From the candidates, pick the one that is the same movement on the same kind of equipment. If no candidate is the same movement, return null. Also describe the movement in one sentence for an illustrator: the equipment, the body position at the start and the body position at the end of one repetition.`;

const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();

export const matchExerciseJob: JobDef<MatchExerciseInput, MatchExerciseOutput> = {
  name: "match_exercise",
  description: "Picks the public exercise (with photos) that is the same movement as the name the person logged, or none.",
  fallbackDescription: "The first candidate when its name equals the exercise name (ignoring case and punctuation); else none.",
  json: true,
  maxTokens: 300,
  output: MatchExerciseSchema,
  check: (o, i) => (o.id === null || i.candidates.some((c) => c.id === o.id) ? null : "id is not one of the candidates"),
  build: (i) => ({
    system: systemPrompt("match_exercise", ROLE, `{"id": string | null (the id of one candidate, or null), "movement": string (max 300 chars)}`),
    messages: [{ role: "user", content: dataPrompt("Pick the matching candidate.", i) }],
  }),
  fallback: (i) => {
    const c = i.candidates[0];
    return { id: c && norm(c.name) === norm(i.exercise) ? c.id : null };
  },
};
