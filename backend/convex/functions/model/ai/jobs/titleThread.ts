import { z } from "zod";
import type { JobDef } from "../runJob";
import { dataPrompt, systemPrompt } from "../promptRules";
import { cleanAiTitle, titleFromMessage } from "../../threadTitle";

export interface TitleThreadInput {
  /** The first user message of the thread. */
  text: string;
  /** The first coach reply, if there is one. */
  reply?: string;
}

const OutputSchema = z.object({
  title: z.string().transform(cleanAiTitle).pipe(z.string().min(1).max(40)),
});
type Out = z.infer<typeof OutputSchema>;

export const titleThreadJob: JobDef<TitleThreadInput, Out> = {
  name: "title_thread",
  description: "A short title (max 40 chars, no quotes, no trailing period) about the topic of a new thread, from its first message and first reply.",
  fallbackDescription: "The plain-code title: the first words of the first message.",
  json: true,
  maxTokens: 200,
  output: OutputSchema,
  build: (i) => ({
    system: systemPrompt("title_thread", "Write a short title for this conversation: at most 40 characters, about the topic, no quotation marks, no period at the end. Use only what was said.", `{"title": string (max 40 chars)}`),
    messages: [{ role: "user", content: dataPrompt("Title this thread.", { text: i.text.slice(0, 1000), reply: (i.reply ?? "").slice(0, 600) }) }],
  }),
  fallback: (i) => ({ title: titleFromMessage(i.text) }),
};
