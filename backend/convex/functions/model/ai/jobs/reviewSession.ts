import type { JobDef } from "../runJob";
import { LIMITS_RULE, TRACKER_RULE, dataPrompt, systemPrompt } from "../promptRules";
import { type LimitForAi, type ReviewDraft, ReviewDraftSchema, type Session } from "../../schema";
import { timeText } from "../../rules/util";
import type { coachPicture } from "./coachPicture";
import { limitsForPrompt, localTime, logForPrompt } from "./shared";

export interface ReviewInput {
  /** The time zone of the user (ADR-039), for the clock times in the prompt. Absent: the deployment's zone. */
  timeZone?: string;
  session: Session;
  /** The session plus the recent sessions of the same activity and focus before it, oldest first (bounded, see inputs.ts). */
  sessions: Session[];
  /** The limits with their records, cleared ones too (ADR-033). */
  limits: LimitForAi[];
  /** The picture of the person as it was BEFORE this session (goals, notes, recent sessions, every exercise with its last sets). Absent in old callers. */
  picture?: ReturnType<typeof coachPicture>;
  /** Plain-code review, computed by the caller from the FULL history. */
  rules: ReviewDraft;
}

const ROLE = `You are the personal coach of the person described in the data. They have just finished the session in "session". Say what a good coach who has trained this person for a long time would say right after it.

The person can see their own log, so do not read it back to them: no counts of exercises or minutes for their own sake, and nothing about what was "not logged". Judge the session. "before" is the picture of the person as it was before this session: the goals in order of priority, the notes, the recent sessions, and exercisesTheUserKnows with the last sets and the best weight of every exercise, whatever the focus of that day was. Compare each exercise with the last time that exercise was done, not only with the last session of the same name, and mind how long ago that was.

The summary is your verdict, in two or three plain sentences: what this session did for what the person wants most, and the one thing that stands out (a real step forward, a set marked failed, a load that came back after a break, something the session lacked for the goal). Say it straight, as you would to someone you respect; praise only what earned it.

The changes are at most five short lines, the ones that matter most, each about one exercise or one point. A line says what moved against last time, with the numbers; a next step (the weight, the reps or the minutes to aim for) goes on at most two lines, for the exercises where it matters most, and the other lines are only reported. Name the biggest real change of the day, up or down, even when it was not planned. A warm-up or cool-down gets no line unless something about it matters. A set marked failed or a comment from the person on an exercise deserves a line when it changes what to do next. When an exercise simply repeated, leave it out.

${LIMITS_RULE} Apply a limit only to the body part and movement it names; a word match is not enough (turning the trunk is not twisting the knee). ${TRACKER_RULE}`;

/** The finished session as the review reads it: sets with the failed mark and the person's comment. */
function finished(s: Session, timeZone?: string) {
  const base = logForPrompt([s], 1, timeZone)[0]!;
  return {
    ...base,
    end: localTime(s.endedAt, timeZone),
    exercises: s.exercises.map((e) => ({
      name: e.name,
      sets: e.sets.map((x) => ("kg" in x ? `${x.reps}x${x.kg}${x.max ? " max" : ""}${x.failed ? " (last rep failed)" : ""}` : timeText(x))).join(", "),
      ...(e.comment ? { commentFromThePerson: e.comment } : {}),
    })),
    ...(s.note ? { note: s.note } : {}),
  };
}

export const reviewSessionJob: JobDef<ReviewInput, ReviewDraft> = {
  name: "review_session",
  description: "The coach's word after a finished session: what it did for the goals, what moved against the last time each exercise was done, what to do next time.",
  fallbackDescription: "Set counts and top sets compared with the previous session of that type.",
  json: true,
  maxTokens: 2500,
  output: ReviewDraftSchema,
  build: (i) => ({
    system: systemPrompt("review_session", ROLE, `{"summary": string (max 400 chars), "changes": string[] (max 5 lines, each max 160 chars)}`),
    messages: [{ role: "user", content: dataPrompt("Review this session.", { session: finished(i.session, i.timeZone), ...(i.picture ? { before: i.picture } : { recentSameType: logForPrompt(i.sessions.filter((x) => x.id !== i.session.id), 6, i.timeZone), limits: limitsForPrompt(i.limits) }) }) }],
  }),
  fallback: (i) => i.rules,
};
