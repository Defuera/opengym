import { z } from "zod";
import type { ChatMessage, ImageInput } from "../provider";
import type { JobDef } from "../runJob";
import { JSON_ONLY, systemPrompt } from "../promptRules";
import type { ProgramValue } from "../../schema";
import { NOT_CONFIGURED_REPLY } from "./chat";

export interface ChatProgramInput {
  /** Assembled context block (same as `chat`: other threads, log, goals, context, file text). */
  contextBlock: string;
  /** This thread's messages including the new user message last. */
  history: ChatMessage[];
  images?: ImageInput[];
  /** Today as "YYYY-MM-DD (Weekday)". */
  today: string;
  /** The program the thread is about, when it exists. */
  currentProgram?: ProgramValue;
  /** The newest proposal of this thread that is ready: the program the person looks at now. */
  openProposal?: ProgramValue;
  /** A proposal of this thread is being written right now. */
  proposalBeingWritten: boolean;
}

export const ChatProgramSchema = z.object({
  text: z.string().min(1).max(4000),
  proposeProgram: z.object({ brief: z.string().min(1).max(1000) }).optional(),
});
export type ChatProgramOutput = z.infer<typeof ChatProgramSchema>;

const ROLE =
  "You are the user's personal coach inside the OpenGym app. This conversation is about a training program of this person. Answer questions as the coach: direct and concrete. When the person gives a program text, asks for a program, or asks to change the proposed or the current program, and you have what you need, set proposeProgram. A separate step writes the program, so do NOT write the program out in text: say in one or two sentences what you will propose. proposeProgram.brief is one or two sentences: what to write or what to change, in your words. Ask first when something needed is missing. Do not set proposeProgram when the person only asks a question.";

const SHAPE = `{"text": string (1..4000, the message the person reads), "proposeProgram"?: {"brief": string (1..1000)}}`;

/** The coach's reply in a thread about a program (ADR-026): a chat message and, when the program should be written now, a brief. Code does the action. */
export const chatProgramJob: JobDef<ChatProgramInput, ChatProgramOutput> = {
  name: "chat_program",
  description: "The coach's reply in a thread about a program. Same context as `chat` plus today, the current program, the program the person looks at and whether one is being written. JSON: the message text and, when the program should be written now, proposeProgram.brief.",
  fallbackDescription: "A fixed 'AI is not configured' reply, no proposal; the message is still stored.",
  json: true,
  maxTokens: 2500,
  output: ChatProgramSchema,
  build: (i) => {
    const history = i.history.slice();
    while (history.length && history[0]!.role !== "user") history.shift();
    const state = [
      `Today: ${i.today}.`,
      i.currentProgram ? `The program the person has now:\n${JSON.stringify(i.currentProgram)}` : "",
      i.openProposal ? `The program you proposed, which the person looks at now:\n${JSON.stringify(i.openProposal)}` : "",
      i.proposalBeingWritten ? "A program proposal is being written right now." : "",
    ].filter(Boolean);
    return {
      system: `${systemPrompt("chat_program", ROLE)}\n\n${JSON_ONLY}\n${SHAPE}\n\nWhat you know about this person (do not invent logged facts beyond it):\n${i.contextBlock}\n\n${state.join("\n\n")}`,
      messages: history,
      images: i.images,
    };
  },
  fallback: () => ({ text: NOT_CONFIGURED_REPLY }),
};
