import type { JobDef } from "../runJob";
import { LIMITS_RULE, dataPrompt, systemPrompt } from "../promptRules";
import { avoidedInPlan } from "../../rules/limits";
import { type ContextItem, type Goal, type Limit, type PlanDraft, type StartProposal, StartProposalSchema, type Session } from "../../schema";
import { activityKey } from "../../sessionShape";
import { contextForPrompt, goalsForPrompt, limitsForPrompt, logForPrompt, type KnownActivity } from "./shared";

/**
 * A typed "Start session" request (ADR-016). `known` is the vocabulary of the FULL log; `sessions` is the recent
 * history of the best-matching activity (bounded, see inputs.ts). Never holds records (ADR-015).
 */
export interface InterpretInput {
  /** What the user typed, 0..200 characters. With a name it is the wish and may be empty. */
  text: string;
  /** The fixed session name (1..40), when the user gave one. The proposal type is always this name. */
  name?: string;
  /** "today": the user wants the one session that fits today. `text` is the wish. No name. */
  mode?: "today";
  /** The pick the app showed (today mode). A suggestion, not an order. */
  hint?: { type: string; focus?: string };
  known: KnownActivity[];
  /** The known activity the text most likely means, when one does. */
  bestMatch?: string;
  sessions: Session[];
  goals: Goal[];
  /** The last sessions of any activity, oldest first: what the body did in the last days. */
  lately: Session[];
  /** Time of the request (ms). */
  now: number;
  /** Equipment and preference notes. */
  context: ContextItem[];
  /** Non-cleared limits. Never holds records. */
  limits: Limit[];
  /** Plain-code plan for the best match (the user's last session of it), or empty. */
  rules: PlanDraft;
}

const SHAPE = `{"kind": "gym" | "activity", "type": string (1..40; the activity; reuse a name from knownActivities when one fits), "focus"?: string (max 40), "minutes"?: int (the duration asked for), "reason"?: string (max 80 chars), "plan"?: {"rationale": string (max 200 chars), "exercises": [{"name": string, "sets": [{"reps": int, "kg": number, "max": boolean}], "note"?: string (max 120 chars)}]}}  // plan is required when kind is "gym", left out when kind is "activity"; at most 12 exercises, at most 10 sets each`;

/** First letter upper case, the text before the first comma, at most 40 characters. The same rule the app uses offline. */
export function nameFromText(text: string): string {
  const first = (text.split(",")[0] ?? "").trim() || text.trim();
  const cut = first.slice(0, 40).trim();
  return cut === "" ? "Gym" : cut.charAt(0).toUpperCase() + cut.slice(1);
}

/** Plain-code fallback: a session with sets under the name from the text (a known spelling when the log has one), with an empty plan. */
export function fallbackProposal(i: Pick<InterpretInput, "text" | "known" | "name"> & Partial<Pick<InterpretInput, "mode" | "hint" | "rules">>): StartProposal {
  if (i.mode === "today" && i.hint) {
    // Today mode: the hinted activity and focus with the rules plan for it (empty only when the log has none).
    const hk = i.known.find((a) => activityKey(a.type) === activityKey(i.hint!.type));
    const type = hk?.type ?? i.hint.type.slice(0, 40);
    const focus = i.hint.focus?.trim() ? i.hint.focus.trim().slice(0, 40) : undefined;
    const plan = i.rules && i.rules.exercises.length > 0 ? i.rules : { rationale: "Empty session. Add what you do.", exercises: [] };
    return { kind: "gym", type, ...(focus ? { focus } : {}), plan };
  }
  const name = i.name?.trim() ? i.name.trim().slice(0, 40) : nameFromText(i.text);
  const known = i.known.find((a) => activityKey(a.type) === activityKey(name));
  return { kind: "gym", type: known?.type ?? name, plan: { rationale: "Empty session. Add what you do.", exercises: [] } };
}

export const interpretRequestJob: JobDef<InterpretInput, StartProposal> = {
  name: "interpret_request",
  description: "Turns a typed request (for example \"quick home session, 15 min\") into a proposal: an activity name (reused from the log when one fits), a focus, and a plan for a session with sets.",
  fallbackDescription: "A session with sets named from the text before the first comma (a known spelling when the log has one) with an empty plan.",
  json: true,
  maxTokens: 4000,
  output: StartProposalSchema,
  // Hard check (ADR-015): an exercise named by an avoid rule makes the plan invalid, like a shape error.
  check: (p, i) => {
    // A request to start a session must come back with something to follow.
    if (p.kind === "gym" && (!p.plan || p.plan.exercises.length === 0)) return "plan.exercises: a session with sets needs at least one exercise";
    const hit = p.plan ? avoidedInPlan(p.plan, i.limits) : null;
    return hit ? `plan.exercises: "${hit}" is marked avoid` : null;
  },
  build: (i) => ({
    system: systemPrompt(
      "interpret_request",
      (i.mode === "today"
        ? `You pick the one session that fits the user today. The user does not want to choose: you decide. Decide the activity and the focus from the log: read lastSessionsOfAnyKind and today. Do not repeat what was trained today or yesterday, pick what is due, follow the user's usual rhythm, and serve the goals. suggestedToday is the pick the user saw: keep it unless the wish or the last sessions give a reason to change it. The wish, when it is not empty, adjusts the session (time, easier or harder, an area to spare or to prefer) and wins over the suggestion. When the wish names an area that feels off, leave out exercises that load that area and say so in the plan rationale in training words. Use kind gym. type must be a name from knownActivities. Write a full plan, never an empty one: take exercises from the log when they fit, take weights from the log, and do not exceed 1.25 times the heaviest weight ever logged for an exercise. The plan must fill the time: count about two minutes per set including rest, so 30 minutes is about 12 to 15 sets over 4 to 6 exercises. An easy session means lighter weights and no sets to the limit, not a plan with one exercise. Name in the plan only what is in the exercises list. Minutes come from the wish; with no time in the wish, use the user's usual session length from the log. Put the minutes and an advised focus (max 40 characters) in the answer. The reason is one short factual line. ${LIMITS_RULE}`
        : i.name
        ? `You turn one request into a proposal for a session to start. The user gave a fixed session name and an optional wish. The name is fixed: put it in type exactly as given and never rename it. The wish describes what the user wants in this session (duration, equipment, body area, easy or hard). With an empty wish, plan a normal session of that activity: from the log when it has sessions of that activity, else about 20 minutes with bodyweight exercises only. Use kind gym and write a full plan: the number of exercises and sets must fit the time asked for (about two minutes per set, including rest), use the equipment and preferences in context (do not assume a gym unless the name is the usual gym), keep to exercises the log shows when they fit, and do not exceed 1.25 times the heaviest weight ever logged for an exercise. Never return an empty plan. Put the duration asked for in minutes, and an advised focus (max 40 characters) when it helps. The reason is one short factual line. ${LIMITS_RULE}`
        : "You turn one typed request into a proposal for a session to start. The user types what they want to do (for example a home session of 15 minutes, a new activity, or a focus). The activity name says where or what: a different place or equipment is a different activity. A session at home is Home and a session in a hotel gym is Hotel gym, never Gym; Gym is only for the user's usual gym. Reuse an activity name from knownActivities, spelled as there, only when the request means that same activity; otherwise give the new activity a short name (one to three words) from the request. Words such as quick, easy or a body area go in focus, not in the name. Use kind gym for a session with sets for that activity (the app then follows a plan of exercises and sets); use kind activity only for time or distance work with no sets. For a session with sets, write the plan: the number of exercises and sets must fit the time the user asked for (about two minutes per set, including rest), use the equipment and preferences in context (do not assume a gym), keep to exercises the log shows when the request matches one of them, and do not exceed 1.25 times the heaviest weight ever logged for an exercise. Fit the plan to the user: read lastSessionsOfAnyKind and today. Do not repeat what was trained today or yesterday; pick areas that are due, and say in the plan rationale what you took into account. Set the difficulty from the log: a user who lifts heavy needs more than two easy bodyweight sets, so use harder variants, more sets, slower tempo or holds, within the limits. A bodyweight set takes about one minute including rest, a loaded set about two. Always write a full plan for a session with sets, also when the request is short (for example only two words) and when the log has no session of that activity: never return an empty plan. When the request gives no duration, plan about 20 minutes. When it names no equipment and it is not the usual gym, use bodyweight exercises only. Put the duration asked for in minutes, and an advised focus (max 40 characters) when it helps. The reason is one short factual line. " + LIMITS_RULE),
      SHAPE,
    ),
    messages: [
      {
        role: "user",
        content: dataPrompt("Interpret this start request.", {
          ...(i.mode === "today" ? { wish: i.text, suggestedToday: i.hint ?? null } : i.name ? { name: i.name, wish: i.text } : { request: i.text }),
          knownActivities: i.known,
          bestMatch: i.bestMatch ?? null,
          today: new Date(i.now).toISOString().slice(0, 10),
          recentLogOfBestMatch: logForPrompt(i.sessions, 6),
          lastSessionsOfAnyKind: logForPrompt(i.lately, 6),
          goals: goalsForPrompt(i.goals.filter((g) => g.status === "active")),
          context: contextForPrompt(i.context),
          limits: limitsForPrompt(i.limits),
          suggestedStart: i.rules,
        }),
      },
    ],
  }),
  fallback: (i) => fallbackProposal(i),
};
