import { localTime } from "./ai/jobs/shared";
import { dayNumber, localDate, programNow } from "./program";
import type { ProgramForCoach } from "./programForCoach";
import { fmtKg } from "./rules/util";
import type { Exercise, Session } from "./schema";
import { activityKey } from "./sessionShape";

/**
 * The facts of one finished session for the review (ADR-041). All numbers are made here, in code, from the history of the person;
 * the review prompt tells the model these are the only numbers it may use. Pure: the caller reads the rows.
 */

/** A log entry with its category, for the body log of the day. */
export interface FactsEntry {
  kind: string;
  text: string;
  at: number;
  /** True when the entry made a session (the log chat, ADR-032): its text is the workout the person wrote, not a body note. */
  madeSession?: boolean;
}

export interface FactsOptions {
  timeZone?: string;
  /** The entries of the person around the session day (any kind; the "Body" ones are kept). */
  entries?: FactsEntry[];
  /** Every live program. */
  programs?: ProgramForCoach[];
}

const DAY = 86_400_000;
/** Sessions of the same activity and focus in this many weeks make "the usual". */
export const USUAL_WEEKS = 8;
/** At least this many such sessions are needed to say what is usual. */
export const USUAL_MIN_SESSIONS = 3;
/** A session within this share of the usual counts as "about the usual". */
const ABOUT = 0.2;

type Set = Exercise["sets"][number];
type Planned = NonNullable<Exercise["planned"]>[number];

const isTimeSet = (x: { minutes?: number }): x is { minutes: number; distanceKm?: number } => x.minutes !== undefined;

/** The best entry of an exercise as text, and its numbers: the heaviest set (then the most reps), or the longest time. Null when it has no entry. */
function best(sets: (Set | Planned)[]): { text: string; kg: number; reps: number; minutes: number } | null {
  let top: { text: string; kg: number; reps: number; minutes: number } | null = null;
  for (const x of sets) {
    const c = isTimeSet(x as { minutes?: number }) ? { text: `${fmtKg((x as { minutes: number }).minutes)} min`, kg: 0, reps: 0, minutes: (x as { minutes: number }).minutes } : { text: `${(x as { reps: number }).reps}x${fmtKg((x as { kg: number }).kg)}`, kg: (x as { kg: number }).kg, reps: (x as { reps: number }).reps, minutes: 0 };
    if (!top || c.minutes > top.minutes || c.kg > top.kg || (c.kg === top.kg && c.reps > top.reps)) top = c;
  }
  return top;
}

const signed = (n: number, unit: string) => `${n > 0 ? "+" : "-"}${fmtKg(Math.abs(n))} ${unit}`;

/** The signed change of the best entry against the earlier one, as text made here. */
function change(now: NonNullable<ReturnType<typeof best>>, was: NonNullable<ReturnType<typeof best>>): string {
  if (now.minutes || was.minutes) return now.minutes === was.minutes ? "same" : signed(now.minutes - was.minutes, "min");
  if (now.kg !== was.kg) return signed(now.kg - was.kg, "kg");
  return now.reps === was.reps ? "same" : `${signed(now.reps - was.reps, "reps")} at the same weight`;
}

/** The work of a list of entries as one number: reps times kg (reps alone when nothing is weighted), or minutes. */
function work(sets: (Set | Planned)[]): number {
  const timed = sets.reduce((n, x) => n + (isTimeSet(x as { minutes?: number }) ? (x as { minutes: number }).minutes : 0), 0);
  if (timed > 0) return timed;
  const reps = sets as { reps: number; kg: number }[];
  const weighted = reps.reduce((n, x) => n + x.reps * x.kg, 0);
  return weighted > 0 ? weighted : reps.reduce((n, x) => n + x.reps, 0);
}

const countText = (sets: (Set | Planned)[]) => `${sets.length} ${sets.length === 1 ? "set" : "sets"}, top ${best(sets)?.text ?? "none"}`;

const median = (xs: number[]): number => {
  const s = xs.slice().sort((a, b) => a - b);
  const m = s.length >> 1;
  return s.length % 2 ? s[m]! : Math.round(((s[m - 1]! + s[m]!) / 2) * 10) / 10;
};

/** How long a session took: the real span of one done in the app, else the minutes written on it. */
const durationOf = (s: Session): number | undefined => (s.endedAt > s.startedAt && s.source !== "import" ? Math.round((s.endedAt - s.startedAt) / 60000) : s.minutes);
const setCount = (s: Session) => s.exercises.reduce((n, e) => n + e.sets.length, 0);

const versus = (now: number, usual: number): "more" | "fewer or shorter" | "about the same" => (Math.abs(now - usual) <= usual * ABOUT ? "about the same" : now > usual ? "more" : "fewer or shorter");

/** The facts of `s`, which is in `all` (the FULL live history, oldest first). */
export function reviewFacts(all: Session[], s: Session, o: FactsOptions = {}) {
  const tz = o.timeZone;
  const earlier = all.filter((x) => x.id !== s.id && x.endedAt <= s.startedAt);
  const exercises = s.exercises.filter((e) => e.sets.length > 0).map((e) => {
    const now = best(e.sets)!;
    const key = activityKey(e.name);
    const last = earlier.slice().reverse().find((x) => x.exercises.some((y) => activityKey(y.name) === key && y.sets.length > 0));
    const was = last ? best(last.exercises.find((y) => activityKey(y.name) === key && y.sets.length > 0)!.sets) : null;
    const lastDay = last ? localDate(last.endedAt, tz) : null;
    const today = localDate(s.endedAt, tz);
    return {
      name: e.name,
      bestToday: now.text,
      firstTime: last === undefined,
      ...(last && was && lastDay ? { lastTime: { date: lastDay, best: was.text }, change: change(now, was), daysSinceLast: Math.max(0, (dayNumber(today) ?? 0) - (dayNumber(lastDay) ?? 0)) } : {}),
    };
  });

  const planned = s.exercises.filter((e) => e.planned !== undefined);
  const skipped = s.skipped ?? [];
  const hasPlan = s.planNote !== undefined || planned.length > 0 || skipped.length > 0;
  const againstPlan = hasPlan
    ? {
        ...(s.planNote ? { planNote: s.planNote } : {}),
        exercises: planned.map((e) => {
          const p = work(e.planned!);
          const d = work(e.sets);
          return { name: e.name, planned: countText(e.planned!), done: countText(e.sets), verdict: d > p ? "more" : d < p ? "less" : "as planned" };
        }),
        skippedPlanned: skipped.map((x) => ({ name: x.name, planned: countText(x.planned) })),
        addedNotPlanned: s.exercises.filter((e) => e.planned === undefined && e.sets.length > 0).map((e) => e.name),
      }
    : undefined;

  const peers = all.filter((x) => x.id !== s.id && x.kind === s.kind && activityKey(x.type) === activityKey(s.type) && activityKey(x.focus ?? "") === activityKey(s.focus ?? "") && x.endedAt <= s.startedAt && x.endedAt > s.startedAt - USUAL_WEEKS * 7 * DAY);
  const minutes = durationOf(s);
  const peerMinutes = peers.map(durationOf).filter((m): m is number => m !== undefined);
  const usual = peers.length >= USUAL_MIN_SESSIONS
    ? { sessions: peers.length, medianSets: median(peers.map(setCount)), setsVsUsual: versus(setCount(s), median(peers.map(setCount))), ...(peerMinutes.length >= USUAL_MIN_SESSIONS ? { medianMinutes: median(peerMinutes), ...(minutes !== undefined ? { durationVsUsual: versus(minutes, median(peerMinutes)) } : {}) } : {}) }
    : undefined;

  const day = localDate(s.endedAt, tz);
  const programs = (o.programs ?? []).filter((p) => p.status === "active").flatMap((p) => {
    const now = programNow(p, day, (week, slot) => all.some((x) => x.programId === p.programId && x.programWeek === week && x.programSlot === slot), () => []);
    if (now.state !== "running") return [];
    // Done = every finished session that ended in the program week (the same week the "of N" slots belong to), up to the day of the
    // reviewed session, which is counted too. Not only sessions linked to a slot: a session started outside the program still counts.
    const weekStart = (dayNumber(p.startsOn) ?? 0) + (now.week - 1) * 7;
    const today = dayNumber(day) ?? weekStart;
    const done = [...all.filter((x) => x.id !== s.id), s].filter((x) => {
      const d = dayNumber(localDate(x.endedAt, tz)) ?? -1;
      return d >= weekStart && d <= Math.min(weekStart + 6, today);
    }).length;
    return [{ title: p.title, week: `${now.week} of ${now.weeks}`, sessionsDoneThisWeek: done, sessionsPlannedThisWeek: now.slots.length, daysToProgramEnd: (dayNumber(p.endsOn) ?? 0) - (dayNumber(day) ?? 0) }];
  });

  const comments = s.exercises.filter((e) => e.comment).map((e) => ({ exercise: e.name, text: e.comment! }));
  const body = (o.entries ?? []).filter((e) => activityKey(e.kind) === "body" && !e.madeSession && e.text.trim() !== "" && localDate(e.at, tz) === day).map((e) => ({ time: localTime(e.at, tz), text: e.text }));

  return {
    session: { activity: s.type, ...(s.focus ? { focus: s.focus } : {}), date: day, ...(minutes !== undefined ? { minutes } : {}), ...(s.distanceKm !== undefined ? { distanceKm: s.distanceKm } : {}), doneSets: setCount(s), ...(usual ? { usual } : {}) },
    exercises,
    ...(againstPlan ? { againstPlan } : {}),
    ...(programs.length > 0 ? { program: programs } : {}),
    ...(comments.length > 0 ? { commentsFromThePerson: comments } : {}),
    ...(s.note ? { noteFromThePerson: s.note } : {}),
    ...(body.length > 0 ? { bodyLogToday: body } : {}),
  };
}

export type ReviewFacts = ReturnType<typeof reviewFacts>;
