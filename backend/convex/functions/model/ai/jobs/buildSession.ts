import type { ImageInput } from "../provider";
import type { JobDef } from "../runJob";
import { JSON_ONLY } from "../promptRules";
import { avoidedInPlan } from "../../rules/limits";
import { nameFromText } from "../../startFallback";
import { type Limit, type StartProposal, StartProposalSchema } from "../../schema";
import type { coachPicture } from "./coachPicture";
import { TIME_RULE } from "./shared";

export interface BuildSessionInput {
  /** The activity the user chose. Fixed. Null when the user typed a free request: the coach names the activity. */
  name: string | null;
  /** The user's note for today, may be empty. */
  note: string;
  /** The free text of a start request with no fixed name (max 2000). */
  request?: string;
  /** On a rebuild: the plan the person saw (exercise names with sets), and the feedback rounds they gave (oldest first, at most 5). */
  previousPlan?: unknown;
  feedbackFromThePerson?: string[];
  /** Every place the person has, with its equipment note ("" = unknown) and whether it was the place of the last session of this activity (ADR-021). */
  placesTheCoachKnows?: { name: string; equipment: string; lastUsedForThisActivity: boolean }[];
  /** The foci the log holds, per activity with sets, with how often each was logged (most used first). The coach reuses one of these names. */
  fociTheUserUses?: { activity: string; foci: { focus: string; timesLogged: number }[] }[];
  picture: ReturnType<typeof coachPicture>;
  limits: Limit[];
  /** Photos of the log entries of the last day. Sent only when the provider takes images. */
  images?: ImageInput[];
}

const SHAPE = `{"kind": "gym", "type": string (the activity, exactly as given; max 40), "focus": string (max 40), "minutes": int, "place"?: string (max 30: a name from placesTheCoachKnows, or a new short name when the request clearly means a place that is not in the list), "reason": string (max 80 chars, why this session today), "plan": {"rationale": string (max 200 chars), "exercises": [{"name": string, "sets": [{"reps": int, "kg": number, "max": boolean}], "note"?: string (max 120 chars)} | {"name": string, "measure": "time", "sets": [{"minutes": number}], "note"?: string (max 120 chars)}]}}  // at most 12 exercises, at most 10 sets each. ${TIME_RULE}`;

const ROLE = `You are the personal coach of the person described in the data. They have chosen today's activity and may have left a note. You decide what the session contains, and you write the session you would hand to this person today. When the request or the note already lists the session (exercises with sets, reps or minutes), that list is the session: keep every exercise, the order and the numbers as written, put the person's instructions for an exercise in its note, and decide only what the list leaves open.

Coach the way a good coach does who has trained this person for a long time: you know what they lift (exercisesTheUserKnows shows every exercise with the last sets and the best weight), what the last weeks looked like, what they want (the goals are in order of priority; a goal with a date sets the direction of the weeks before it), and what they train around (limits). The note for today comes from the person and you take it seriously, in proportion: it shapes the session, it does not cancel the training. logEntriesFromTheUser are free notes the person wrote in the last days; the photos of the last day are attached. In recentSessions an exercise may carry a comment from the person: it says how that exercise went on that day (a pain, an effort, a machine setting), so weigh it by its date.

A session moves the person forward. For each exercise start from lastSets: when that work was done, a few exercises get a real step (one more set, two or three reps, the smallest weight step the place has, or 15 seconds on a hold) and the others repeat; one token rep on every exercise is not progress, and warm-up and mobility work stays as it is. Never give less than last time without a cause in the data (a limit, the note for today, pain or tiredness in the log); when you give less, name the cause in the note of that exercise. A limit that says light or within comfort still allows small steps. When the person asks for more time than usual, fill it with training that serves the goals (more work sets, exercises the limits name as good to do, weak points from the notes), not with easy filler.

When previousPlan and feedbackFromThePerson are present, the person saw that plan and asked for a change: rebuild the session so that the feedback holds.

placesTheCoachKnows says where the person trains and what is there; choose today's place (the note may say it, otherwise the one last used for this activity) and use only equipment that place has. A place with an empty equipment text is unknown: prefer bodyweight and what the person's log shows there.

The focus is the short name of the kind of session (Upper, Legs, Full body), one or two words. fociTheUserUses lists the names this person already has for each activity, with how often each was logged: use one of them, the closest one, and prefer the names logged often. Give a new focus only when the session is truly a different kind from all of them. What is special about today (a goal, a mix, a place) goes in reason, not in focus. Never put the request or the note in focus.

Two things are fixed. Never use an exercise or a movement that a limit marks avoid. The name of the activity is not yours to change; when activity is null, name it from the request (one to three words), and reuse a name from the person's log when the request means the same activity.`;

/** One prompt for "build today's session": the picture of the user, a short role, the hard constraints. */
export const buildSessionJob: JobDef<BuildSessionInput, StartProposal> = {
  name: "build_session",
  description: "Builds today's session for the chosen activity from the full picture of the user and the note for today.",
  fallbackDescription: "The plain rules plan for the activity.",
  json: true,
  maxTokens: 6000,
  output: StartProposalSchema,
  check: (p, i) => {
    if (p.kind !== "gym") return 'kind: a session is always "gym"';
    if (!p.plan || p.plan.exercises.length === 0) return "plan.exercises: a session needs at least one exercise";
    const hit = avoidedInPlan(p.plan, i.limits);
    return hit ? `plan.exercises: "${hit}" is marked avoid` : null;
  },
  build: (i) => ({
    system: `JOB: build_session\n\n${ROLE}\n\n${JSON_ONLY}\n${SHAPE}`,
    messages: [{ role: "user", content: `Build today's session.\n\nINPUT_JSON:\n${JSON.stringify({ activity: i.name, ...(i.request !== undefined ? { request: i.request } : {}), noteForToday: i.note || null, ...(i.placesTheCoachKnows ? { placesTheCoachKnows: i.placesTheCoachKnows } : {}), ...(i.fociTheUserUses && i.fociTheUserUses.length > 0 ? { fociTheUserUses: i.fociTheUserUses } : {}), ...(i.feedbackFromThePerson ? { ...(i.previousPlan ? { previousPlan: i.previousPlan } : {}), feedbackFromThePerson: i.feedbackFromThePerson } : {}), ...i.picture })}` }],
    images: i.images,
  }),
  fallback: (i) => ({ kind: "gym", type: i.name ?? nameFromText(i.request ?? ""), plan: { rationale: "Empty session. Add what you do.", exercises: [] } }),
};
