import { z } from "zod";
import type { JobDef } from "../run-job";
import { dataPrompt, systemPrompt } from "../prompt-rules";
import { truncate } from "../../rules/util";

export interface SummariseInput {
  title: string;
  messages: { role: "user" | "assistant"; text: string }[];
}

const OutputSchema = z.object({ summary: z.string().min(1).max(400) });
type Out = z.infer<typeof OutputSchema>;

export const summariseThreadJob: JobDef<SummariseInput, Out> = {
  name: "summarise_thread",
  description: "Writes a short summary of a thread (max 400 chars) that other threads' coach replies can read.",
  fallbackDescription: "The last user message, truncated.",
  json: true,
  maxTokens: 300,
  output: OutputSchema,
  build: (i) => ({
    system: systemPrompt("summarise_thread", "Summarise the conversation in at most 400 characters: what the user wants, decisions made, what the coach advised about training. Use only what was said.", `{"summary": string (max 400 chars)}`),
    messages: [{ role: "user", content: dataPrompt("Summarise this thread.", { title: i.title, messages: i.messages.slice(-30) }) }],
  }),
  fallback: (i) => {
    const last = [...i.messages].reverse().find((m) => m.role === "user");
    return { summary: truncate(last?.text ?? i.title, 400) };
  },
};
