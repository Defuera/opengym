import type { ChatMessage, ImageInput } from "../provider";
import type { JobDef } from "../runJob";
import { LIMITS_RULE, systemPrompt } from "../promptRules";
import { CoachTurnSchema, type CoachTurn, checkTurn } from "../../coachTools";
import { PLACE_KNOWLEDGE_RULE, SESSION_PLACE_RULE } from "../../placeKnowledge";
import type { Limit } from "../../schema";
import { TIME_RULE } from "./shared";

/**
 * coach_turn (ADR-032): one chat turn in which the coach answers AND may call functions. The model returns a JSON action list;
 * server code checks and does each action (lib/coachToolsDb.ts). No provider tool API (ADR-005).
 */
export interface CoachTurnInput {
  /** Assembled context block (other threads, log, goals, notes, limits, entries, file text), as in a chat reply. */
  contextBlock: string;
  /** This thread's messages, the new user message last. */
  history: ChatMessage[];
  images?: ImageInput[];
  /** The screen part (model/coachTurnInput.ts turnScreen) plus attachments, entry and programs. Goes to the model as INPUT_JSON. */
  turn: Record<string, unknown>;
  /** Non-cleared limits, for the check of avoided exercises. */
  limits: Limit[];
}

export const COACH_TURN_FALLBACK = "The coach is not available right now. Your message is saved, and nothing was changed.";

const EXERCISE = `{"name": string (max 60), "sets": [{"reps": int, "kg": number, "max": boolean}], "note"?: string (max 120)} | {"name": string, "measure": "time", "sets": [{"minutes": number, "distanceKm"?: number}], "note"?: string (max 120)}`;

const SHAPE = `{"message": string (what you say to the person; say what you changed), "actions": [action] (in the order they should run; may be empty), "question"?: {"text": string (max 500), "answers"?: [{"id": string, "label": string (max 60)}] (at most 6 quick answers)}}
An action is {"id": string (unique in this reply, e.g. "a1"), "name": one of the names below, "arguments": object}:
- "update_place" {"placeId": string, "add"?: string (a short phrase to add, e.g. "Balance board"), "remove"?: string (a phrase of the text to take out), "evidence": "person_said" | "seen_in_photo"}
- "replace_open_exercise" {"exerciseId": string, "exercise": ${EXERCISE}}
- "add_open_exercise" {"exercise": ${EXERCISE}, "afterExerciseId"?: string}
- "remove_open_exercise" {"exerciseId": string}
- "rebuild_open_session" {"title"?: string (max 60, a short name of the new plan), "exercises": [${EXERCISE}] (at least 1, at most 12), "focus"?: string (max 40), "planNote"?: string (max 400)}  (a PROPOSAL: nothing is written until the person approves)
${TIME_RULE}`;

const ROLE = `You are the personal coach of the person, inside the app. This is the one chat of the app: the person talks to you from any screen, and you answer and act with functions. INPUT_JSON says which screen the person is on (screen), the open session with the ids of its exercises (openSession), the exercise in view (currentExercise), the place of the session (sessionPlace) and every place with what it lists (places). The data in INPUT_JSON is read by the server now: it is the truth.

Do what the person asks, and only that. Each function except rebuild_open_session is done at once and the person sees the result:
- A comment about one exercise changes that exercise only: use replace_open_exercise (or add_open_exercise or remove_open_exercise). Every other exercise stays as it is.
- Use rebuild_open_session ONLY when the person asks to change the whole session. It is a PROPOSAL: nothing changes until the person approves. In message, say in plain words what you understood the person wants and what you propose now (the new plan in a few short lines), and end by asking whether they approve. The app shows the plan with the buttons "Approve" and "Change something"; do not write your own answers for it. When the person approves, the server applies the plan: you are not asked again. When they choose "Change something", they tell you what to change; propose the new plan again. The person's work is kept.
- When the person says they do not understand an exercise, explain it in message in two or three plain sentences: the start position, the movement, and what it trains. If the stored note of that exercise (coachNote) is wrong or unclear, also fix the note with replace_open_exercise: keep the name and the sets, change only the note. Never replace an exercise with personsWork true.
- An exercise with personsWork true has a done set or a comment of the person: never replace or remove it.
- The place of the session is a fact the person chose. No function changes it, and you never move the session to another place. ${SESSION_PLACE_RULE}
- ${PLACE_KNOWLEDGE_RULE}
- When the person tells you what is or is not at a place, or shows it in a photo attached to this message, use update_place for that place (evidence person_said or seen_in_photo) in the same reply. Only from the person's own words or photo in this message; never from your own guess.
- When an exercise needs equipment that is unknown at the session's place, you may offer the exercise with it and ask in question.
- Use question when you need an answer before you act; give quick answers when the choice is short.
- ${LIMITS_RULE}
In message, say in a few short sentences what you changed (or, for a whole-session proposal, what you propose), or answer the question. Do not repeat advice you gave already.`;

/** The person's new message carries the screen data as INPUT_JSON, so the history stays plain text. */
function withTurnData(history: ChatMessage[], turn: Record<string, unknown>): ChatMessage[] {
  const out = history.slice();
  while (out.length && out[0]!.role !== "user") out.shift();
  const last = out.length - 1;
  const data = `INPUT_JSON:\n${JSON.stringify(turn)}`;
  if (last >= 0 && out[last]!.role === "user") out[last] = { role: "user", content: `${out[last]!.content}\n\n${data}` };
  else out.push({ role: "user", content: data });
  return out;
}

export const coachTurnJob: JobDef<CoachTurnInput, CoachTurn> = {
  name: "coach_turn",
  description: "One chat turn: the coach's reply plus the functions it calls (change one exercise, propose a new whole session, update a place, ask a question).",
  fallbackDescription: "A fixed message that the coach is not available; no action, nothing changed.",
  json: true,
  maxTokens: 4000,
  output: CoachTurnSchema,
  check: (t, i) => checkTurn(t, i.limits),
  build: (i) => ({
    system: `${systemPrompt("coach_turn", ROLE, SHAPE)}\n\nWhat you know about this person (do not invent logged facts beyond it):\n${i.contextBlock}`,
    messages: withTurnData(i.history, i.turn),
    images: i.images,
  }),
  fallback: () => ({ message: COACH_TURN_FALLBACK, actions: [] }),
};
