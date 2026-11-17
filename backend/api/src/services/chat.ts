import { randomUUID } from "node:crypto";
import { chatJob, extractFromChatJob } from "../ai/jobs";
import type { AiRunner } from "../ai/run-job";
import { truncate } from "../rules/util";
import type { Repositories } from "../repositories/types";
import type { ContextItem, Goal, Message } from "../schema";
import { assembleCoachContext } from "./coach-context";
import type { Refresher } from "./refresh";

export interface ChatResult {
  userMessage: Message;
  assistantMessage: Message;
  extracted: { goals: Goal[]; context: ContextItem[] };
}

/** Returns null when the thread does not exist. */
export async function postChatMessage(
  deps: { repos: Repositories; ai: AiRunner; refresher: Refresher; now: () => number },
  threadId: string,
  text: string,
  fileIds: string[],
): Promise<ChatResult | null> {
  const { repos, ai, refresher, now } = deps;
  const thread = repos.threads.get(threadId);
  if (!thread) return null;

  const userMessage = repos.threads.addMessage({ id: randomUUID(), threadId, role: "user", text, fileIds, sources: [], createdAt: now() });

  const coach = await assembleCoachContext(repos, threadId, fileIds, !!ai.provider?.supportsImages);
  const history = repos.threads.messages(threadId).slice(-20).map((m) => ({ role: m.role, content: m.text }));
  const existingContext = repos.context.list().filter((c) => c.active).map((c) => c.text);
  const existingGoals = repos.goals.list().map((g) => g.title);

  const [reply, extract] = await Promise.all([
    ai.run(chatJob, { contextBlock: coach.contextBlock, history, images: coach.images }),
    ai.run(extractFromChatJob, { text, existingContext, existingGoals }),
  ]);

  const assistantMessage = repos.threads.addMessage({
    id: randomUUID(),
    threadId,
    role: "assistant",
    text: reply.value,
    fileIds: [],
    sources: reply.path === "ai" ? coach.sources : [],
    createdAt: now(),
  });

  const goals: Goal[] = [];
  const context: ContextItem[] = [];
  const knownCtx = new Set(existingContext.map((t) => t.toLowerCase()));
  const knownGoals = new Set(existingGoals.map((t) => t.toLowerCase()));
  for (const c of extract.value.context) {
    if (knownCtx.has(c.text.toLowerCase())) continue;
    context.push(repos.context.put({ id: randomUUID(), text: c.text, topic: c.topic, active: true, source: "ai", threadId, createdAt: now() }));
  }
  for (const g of extract.value.goals) {
    if (knownGoals.has(g.title.toLowerCase())) continue;
    goals.push(repos.goals.put({ ...g, id: randomUUID(), status: "active", source: "ai", threadId, createdAt: now() }));
  }

  repos.threads.put({ ...thread, updatedAt: now(), lastMessage: truncate(assistantMessage.text, 200) });
  refresher.threadChanged(threadId);
  if (goals.length || context.length) refresher.factsChanged();

  return { userMessage, assistantMessage, extracted: { goals, context } };
}
