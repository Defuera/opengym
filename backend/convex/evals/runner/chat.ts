import { chatJob } from "../../functions/model/ai/jobs/chat";
import type { ChatMessage } from "../../functions/model/ai/provider";
import { type Logger, runJob } from "../../functions/model/ai/runJob";
import { CHAT_CONTEXT_ITEMS, CHAT_GOALS, CHAT_HISTORY_MESSAGES, CHAT_RECENT_SESSIONS } from "../../functions/model/chatInput";
import { assembleCoachContext } from "../../functions/model/coachContext";
import type { ChatSubject } from "../assertions/subject";
import { persona, placeOf } from "../fixtures";
import type { ChatCase } from "../types";
import type { CaseOutput, RunCtx } from "./types";

const silent: Logger = { info() {}, warn() {}, error() {} };

/** chat as the server does it, turn by turn: the bounded context of the person, this thread's last messages (the coach's own earlier answers included), runJob. */
export async function runChat(c: ChatCase, ctx: RunCtx): Promise<CaseOutput> {
  const p = persona(c.persona);
  const place = c.place ? placeOf(p, c.place) : null;
  const data = {
    otherThreads: [],
    sessions: p.sessions.slice(-CHAT_RECENT_SESSIONS),
    goals: p.goals.filter((g) => g.status === "active").slice(-CHAT_GOALS),
    context: p.context.filter((x) => x.active).slice(-CHAT_CONTEXT_ITEMS),
    limits: p.limits.filter((l) => l.status !== "cleared"),
    entries: p.entries,
  };
  const coach = assembleCoachContext(data, [], ctx.provider.supportsImages, []);
  const history: ChatMessage[] = [];
  const turns: ChatSubject["turns"] = [];
  const paths: ("ai" | "fallback")[] = [];
  const reasons: string[] = [];
  for (const user of c.turns) {
    history.push({ role: "user", content: user });
    const r = await runJob(chatJob, { contextBlock: coach.contextBlock, history: history.slice(-CHAT_HISTORY_MESSAGES), ...(place ? { place: { name: place.name, equipment: place.text } } : {}) }, ctx.provider, silent);
    paths.push(r.path);
    if (r.reason) reasons.push(r.reason);
    history.push({ role: "assistant", content: r.value });
    turns.push({ user, assistant: r.value });
  }
  return { subject: { job: "chat", persona: p, turns }, paths, fallbackReasons: reasons, final: { turns } };
}
