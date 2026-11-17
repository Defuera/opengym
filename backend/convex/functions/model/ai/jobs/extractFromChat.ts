import { z } from "zod";
import type { JobDef } from "../runJob";
import { dataPrompt, systemPrompt } from "../promptRules";
import { ContextInputSchema, GoalInputSchema } from "../../schema";

export interface ExtractInput {
  text: string;
  existingContext: string[];
  existingGoals: string[];
}

export const ExtractOutputSchema = z.object({
  goals: z.array(GoalInputSchema).max(3).default([]),
  context: z.array(ContextInputSchema).max(3).default([]),
});
export type ExtractOutput = z.infer<typeof ExtractOutputSchema>;

export const extractFromChatJob: JobDef<ExtractInput, ExtractOutput> = {
  name: "extract_from_chat",
  description: "Turns statements in a user message into context items (e.g. 'ankle felt tight after squats' -> topic 'ankle') and explicit wishes into goals.",
  fallbackDescription: "Nothing is extracted.",
  json: true,
  maxTokens: 1500,
  output: ExtractOutputSchema as z.ZodType<ExtractOutput>,
  build: (i) => ({
    system: systemPrompt(
      "extract_from_chat",
      "From the user's message, extract (a) context notes: things the planner should remember, such as a body part that felt tight after an exercise, equipment limits, schedule limits; keep them as the user's own words, short, with a one-word topic (for example 'ankle'); (b) goals: only explicit wishes ('I want to bench 80 kg', 'train 3 times a week'). Extract nothing that was not said. Return empty lists when nothing qualifies. Do not add advice or medical interpretation.",
      `{"goals": [{"title": string (max 80), "kind": "strength" | "consistency" | "work_around" | "custom", "exercise"?: string, "targetKg"?: number, "sessionsPerWeek"?: int}], "context": [{"text": string (max 300), "topic": string (max 30)}]}`,
    ),
    messages: [{ role: "user", content: dataPrompt("Extract from this message.", { message: i.text, alreadyKnownContext: i.existingContext, alreadyKnownGoals: i.existingGoals }) }],
  }),
  fallback: () => ({ goals: [], context: [] }),
};
