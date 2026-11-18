import type { JobDef } from "../runJob";
import { JSON_ONLY } from "../promptRules";
import { avoidedInPlan } from "../../rules/limits";
import { type Limit, type StartProposal, StartProposalSchema } from "../../schema";
import type { coachPicture } from "./coachPicture";
import { TIME_RULE } from "./shared";

export interface BuildSessionInput {
  /** The activity the user chose. Fixed. */
  name: string;
  /** The user's note for today, may be empty. */
  note: string;
  picture: ReturnType<typeof coachPicture>;
  limits: Limit[];
}

const SHAPE = `{"kind": "gym", "type": string (the activity, exactly as given), "focus": string (max 40), "minutes": int, "reason": string (max 80 chars, why this session today), "plan": {"rationale": string (max 200 chars), "exercises": [{"name": string, "sets": [{"reps": int, "kg": number, "max": boolean}], "note"?: string (max 120 chars)} | {"name": string, "measure": "time", "sets": [{"minutes": number}], "note"?: string (max 120 chars)}]}}  // at most 12 exercises, at most 10 sets each. ${TIME_RULE}`;

const ROLE = `You are the personal coach of the person described in the data. They have chosen today's activity and may have left a note. You decide what the session contains, and you write the session you would hand to this person today.

Coach the way a good coach does who has trained this person for a long time: you know what they lift (exercisesTheUserKnows shows every exercise with the last sets and the best weight), what the last weeks looked like, what they want (the goals are in order of priority; a goal with a date sets the direction of the weeks before it), and what they train around (limits). The note for today comes from the person and you take it seriously, in proportion: it shapes the session, it does not cancel the training.

Three things are fixed. Never use an exercise or a movement that a limit marks avoid. Use training words only: no diagnosis and no medical language. The name of the activity is not yours to change.`;

/** One prompt for "build today's session": the picture of the user, a short role, the hard constraints. */
export const buildSessionJob: JobDef<BuildSessionInput, StartProposal> = {
  name: "build_session",
  description: "Builds today's session for the chosen activity from the full picture of the user and the note for today.",
  fallbackDescription: "The plain rules plan for the activity.",
  json: true,
  maxTokens: 6000,
  output: StartProposalSchema,
  check: (p, i) => {
    if (!p.plan || p.plan.exercises.length === 0) return "plan.exercises: a session needs at least one exercise";
    const hit = avoidedInPlan(p.plan, i.limits);
    return hit ? `plan.exercises: "${hit}" is marked avoid` : null;
  },
  build: (i) => ({
    system: `JOB: build_session\n\n${ROLE}\n\n${JSON_ONLY}\n${SHAPE}`,
    messages: [{ role: "user", content: `Build today's session.\n\nINPUT_JSON:\n${JSON.stringify({ activity: i.name, noteForToday: i.note || null, ...i.picture })}` }],
  }),
  fallback: (i) => ({ kind: "gym", type: i.name, plan: { rationale: "Empty session. Add what you do.", exercises: [] } }),
};
