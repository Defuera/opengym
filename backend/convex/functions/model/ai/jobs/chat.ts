import { z } from "zod";
import type { ChatMessage, ImageInput } from "../provider";
import type { JobDef } from "../runJob";
import { LIMITS_RULE, systemPrompt } from "../promptRules";

export interface ChatInput {
  /** Assembled context block (other threads, log, goals, context, file text). */
  contextBlock: string;
  /** This thread's messages including the new user message last. */
  history: ChatMessage[];
  images?: ImageInput[];
}

export const NOT_CONFIGURED_REPLY =
  "The AI coach is not available right now (AI is not configured or did not answer). Your message is saved.";

export const chatJob: JobDef<ChatInput, string> = {
  name: "chat",
  description: "The coach's reply in a thread. Reads this thread, summaries of other threads, the recent log, goals, active context and attached files; speaks about training choices only. Plain text.",
  fallbackDescription: "A fixed 'AI is not configured' reply; the message is still stored.",
  json: false,
  maxTokens: 2500,
  output: z.string().min(1),
  build: (i) => {
    const history = i.history.slice();
    while (history.length && history[0]!.role !== "user") history.shift();
    return {
      system: `${systemPrompt(
        "chat",
        "You are the user's gym coach inside the OpenGym app. Answer in plain text (no JSON), short and practical, like a coach texting. You may use the context below, including text from files the user attached, but only talk about training choices: what to do, how heavy, how often. If the user mentions a body part feeling tight or sore, respond only with training adjustments. " + LIMITS_RULE,
      )}\n\nContext you may use (do not claim anything beyond it):\n${i.contextBlock}`,
      messages: history,
      images: i.images,
    };
  },
  fallback: () => NOT_CONFIGURED_REPLY,
};
