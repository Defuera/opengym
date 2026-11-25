import { coachTurnJob } from "../../functions/model/ai/jobs/coachTurn";
import type { ChatMessage } from "../../functions/model/ai/provider";
import { type Logger, runJob } from "../../functions/model/ai/runJob";
import { CHAT_CONTEXT_ITEMS, CHAT_GOALS, CHAT_HISTORY_MESSAGES, CHAT_RECENT_SESSIONS } from "../../functions/model/chatInput";
import { assembleCoachContext } from "../../functions/model/coachContext";
import { knowledgeOf } from "../../functions/model/placeKnowledge";
import type { ChatSubject } from "../assertions/subject";
import { persona, placeOf } from "../fixtures";
import type { ChatCase } from "../types";
import type { CaseOutput, RunCtx } from "./types";

const silent: Logger = { info() {}, warn() {}, error() {} };

/** The coach turn as the server does it for a plain chat, turn by turn: the bounded context of the person, this thread's last messages (the coach's own earlier answers included), runJob. Only the message is judged. */
export async function runChat(c: ChatCase, ctx: RunCtx): Promise<CaseOutput> {
  const p = persona(c.persona);
  const place = c.place ? placeOf(p, c.place) : null;
  const limits = p.limits.filter((l) => l.status !== "cleared");
  const data = {
    otherThreads: [],
    sessions: p.sessions.slice(-CHAT_RECENT_SESSIONS),
    goals: p.goals.filter((g) => g.status === "active").slice(-CHAT_GOALS),
    context: p.context.filter((x) => x.active).slice(-CHAT_CONTEXT_ITEMS),
    limits,
    entries: p.entries,
  };
  const coach = assembleCoachContext(data, [], ctx.provider.supportsImages, []);
  const at = c.session ? placeOf(p, c.session.place) : null;
  const turn = {
    screen: "chat",
    openSession: at ? { id: "eval-open", activity: "Gym", place: at.name, exercises: [] } : null,
    ...(at ? { sessionPlace: { placeId: at.placeId, name: at.name } } : {}),
    ...(place ? { placeInView: { placeId: place.placeId, name: place.name } } : {}),
    places: (c.session ? p.places : place ? [place] : []).map((x) => ({ placeId: x.placeId, name: x.name, equipment: x.text, knowledge: knowledgeOf(x), ...(at && x.placeId === at.placeId ? { isSessionPlace: true } : {}) })),
  };
  const history: ChatMessage[] = [];
  const turns: ChatSubject["turns"] = [];
  const paths: ("ai" | "fallback")[] = [];
  const reasons: string[] = [];
  for (const user of c.turns) {
    history.push({ role: "user", content: user });
    const r = await runJob(coachTurnJob, { contextBlock: coach.contextBlock, history: history.slice(-CHAT_HISTORY_MESSAGES), turn, limits }, ctx.provider, silent);
    paths.push(r.path);
    if (r.reason) reasons.push(r.reason);
    history.push({ role: "assistant", content: r.value.message });
    turns.push({ user, assistant: r.value.message, actions: r.value.actions.map((a) => a.name) });
  }
  return { subject: { job: "chat", persona: p, turns }, paths, fallbackReasons: reasons, final: { turns } };
}
