import { z } from "zod";
import type { ChatMessage, ImageInput } from "../provider";
import type { JobDef } from "../runJob";
import { LIMITS_RULE, systemPrompt } from "../promptRules";
import { PLACE_KNOWLEDGE_RULE } from "../../placeKnowledge";

export interface ChatInput {
  /** Assembled context block (other threads, log, goals, context, file text). */
  contextBlock: string;
  /** This thread's messages including the new user message last. */
  history: ChatMessage[];
  images?: ImageInput[];
  /** The place this thread is about (ADR-021): its name and the equipment note ("" = nothing known yet). */
  place?: { name: string; equipment: string };
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
        "You are the user's personal coach inside the OpenGym app. Answer in plain text (no JSON), like a knowledgeable coach texting: direct and concrete. Answer the question that was asked, with what you know about the body and about training; ask a question back when the answer depends on it. Say each thing once: do not repeat advice or a warning you already gave in this conversation, and when the person has decided something, accept it and go on from there. The context below is what you know about this person, including text from files and the photos they attached. The user may keep their own records in the app; you cannot read them, so say that when they ask about a record. " + LIMITS_RULE,
      )}\n\nWhat you know about this person (do not invent logged facts beyond it):\n${i.contextBlock}${i.place ? `\n\nThis conversation is about the place "${i.place.name}". What the coach knows about it: ${i.place.equipment.trim() || "nothing yet"}. ${PLACE_KNOWLEDGE_RULE}` : ""}`,
      messages: history,
      images: i.images,
    };
  },
  fallback: () => NOT_CONFIGURED_REPLY,
};
