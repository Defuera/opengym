import type { ImageInput } from "../provider";
import type { JobDef } from "../runJob";
import { JSON_ONLY } from "../promptRules";
import { limitsForPrompt } from "../../rules/limits";
import { checkProgramValue } from "../../program";
import { type Limit, type ProgramBuild, type ProgramValue, ProgramBuildSchema } from "../../schema";
import { TIME_RULE } from "./shared";

export interface BuildProgramInput {
  /** Today as "YYYY-MM-DD (Weekday)" in the owner's time zone. */
  today: string;
  /** What the person pasted or typed: a written program, or a wish. */
  request: string;
  /** On a rebuild: the program the person saw (the value of the previous proposal) and the feedback rounds (oldest first, at most 5). */
  previousProgram?: ProgramValue;
  feedbackFromThePerson?: string[];
  /** When the proposal changes a program that exists: that program as it is now. */
  currentProgram?: ProgramValue;
  /** Goals in order of priority, as the coach picture gives them. */
  goalsInOrderOfPriority: unknown[];
  limits: Limit[];
  /** Every place the person has, with its equipment note ("" = unknown). */
  placesTheCoachKnows: { name: string; equipment: string }[];
  /** Files of the chat the proposal was made in: the text of documents, the names of images. The images themselves are in `images`. */
  attachedFiles?: { name: string; text: string }[];
  attachedImages?: string[];
  images?: ImageInput[];
  /** The exercises of the log (at most 60): the person's own names, the last sets, the best weight. Never records (ADR-015). */
  exercisesTheUserKnows: { name: string; lastSets: string; bestKg: number }[];
}

const EXERCISE = `{"name": string, "sets": int (how many sets), "reps": int, "kg": number, "note"?: string (max 120 chars)} | {"name": string, "sets": int (how many holds or rides), "minutes": number (of each), "note"?: string (max 120 chars)}`;
const SESSION = `{"key": string (1..12 chars), "title": string (max 40), "activity": string (max 40), "exercises": [${EXERCISE}] (1..14), "note"?: string (max 200)}`;
const SHAPE = `{"title": string (max 60), "purpose": string (max 300), "startsOn": "YYYY-MM-DD", "endsOn": "YYYY-MM-DD", "week": [string] (1..10 session keys of one week, in order; a key may repeat), "phases": [{"title": string (max 40), "weekFrom": int (>= 1), "weekTo": int (>= weekFrom), "note": string (max 400, may be ""), "sessions": [${SESSION}] (1..8)}] (1..8), "rules": [string (max 300)] (0..12), "tests": [string (max 200)] (0..12), "reason": string (max 200 chars, one line the person reads)}  // the program lasts at most 26 weeks; the phases are in order, start at week 1, leave no gap, do not overlap and cover every week from startsOn to endsOn. ${TIME_RULE}`;

const ROLE = `You are the personal coach of the person described in the data. They ask you for a training program: a plan over several weeks with phases, the sessions of each phase and the rules and tests that go with it. You write the program the person will agree to, and then follow week by week.

When the request already is a written program, that program is the program: keep its sessions, exercises, order, numbers, rules and tests as written and only give it the structure (phases, weeks, session keys). A session is written out in full for every phase: a later phase repeats the session with that phase's numbers and additions. "week" lists the session keys of one week in order. When the person gives an end date or a number of weeks, startsOn is today unless they name another start. Use the person's own exercise names from exercisesTheUserKnows when the same exercise is meant. kg is 0 when the text gives no weight. Holds in seconds become minutes (30 s = 0.5). A bike or a walk day is a session with one time exercise.

When the request is a wish, write the program a good coach would write for this person: you know what they lift (exercisesTheUserKnows), what they want (the goals are in order of priority), where they train (placesTheCoachKnows) and what they train around (limits; never use a movement a limit marks avoid).

The person may attach files or photos (attachedFiles, attachedImages): a written program may be in them.

When previousProgram and feedbackFromThePerson are present, the person saw that program and asked for a change: rebuild it so that the feedback holds. When currentProgram is present, it is the program the person has now: return the whole program with the change from the request made.`;

/** One prompt for "build a program": the picture of the user in short, the request, a role, the hard constraints. No code fallback (a program cannot be made by rules). */
export const buildProgramJob: JobDef<BuildProgramInput, ProgramBuild> = {
  name: "build_program",
  description: "Builds a training program (phases, sessions, rules, tests) from a pasted program or a wish.",
  fallbackDescription: "None: the proposal fails and the person tries again.",
  json: true,
  maxTokens: 16_000,
  output: ProgramBuildSchema,
  check: (p, i) => checkProgramValue(p, i.limits),
  build: (i) => ({
    system: `JOB: build_program\n\n${ROLE}\n\n${JSON_ONLY}\n${SHAPE}`,
    messages: [
      {
        role: "user",
        content: `Build the program.\n\nINPUT_JSON:\n${JSON.stringify({
          today: i.today,
          request: i.request,
          ...(i.feedbackFromThePerson ? { ...(i.previousProgram ? { previousProgram: i.previousProgram } : {}), feedbackFromThePerson: i.feedbackFromThePerson } : {}),
          ...(i.currentProgram ? { currentProgram: i.currentProgram } : {}),
          goalsInOrderOfPriority: i.goalsInOrderOfPriority,
          limits: limitsForPrompt(i.limits),
          placesTheCoachKnows: i.placesTheCoachKnows,
          exercisesTheUserKnows: i.exercisesTheUserKnows,
          ...(i.attachedFiles?.length ? { attachedFiles: i.attachedFiles } : {}),
          ...(i.attachedImages?.length ? { attachedImages: i.attachedImages } : {}),
        })}`,
      },
    ],
    ...(i.images?.length ? { images: i.images } : {}),
  }),
  // Never used as an answer: jobs/programs:build marks the proposal failed when the path is not "ai".
  fallback: (i) => ({ title: "Program", purpose: "", startsOn: i.today.slice(0, 10), endsOn: i.today.slice(0, 10), week: ["A"], phases: [], rules: [], tests: [], reason: "" }),
};
