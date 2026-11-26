import { PROGRAM_MAX_WEEKS } from "../lib/constants";
import { timezoneOf } from "./timezone";
import { avoidedInPlan } from "./rules/limits";
import type { Exercise, Limit, PlanExercise, ProgramPhase, ProgramSession, ProgramValue } from "./schema";
import { activityKey } from "./sessionShape";

const DAY = 86_400_000;

/** The day number of "YYYY-MM-DD" (days since 1970-01-01), or null when it is not a real calendar date ("2026-02-30"). */
export function dayNumber(ymd: string): number | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(ymd);
  if (!m) return null;
  const ms = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  const d = new Date(ms);
  return d.toISOString().slice(0, 10) === ymd ? Math.round(ms / DAY) : null;
}

/** The calendar day of a moment in a time zone (default: `timezoneOf()`; the callers pass the zone of the user, ADR-039), as "YYYY-MM-DD". */
export function localDate(ms: number, timeZone: string = timezoneOf()): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date(ms));
}

/** How many weeks a program spans: both days count, so 1 Dec to 7 Dec is one week and 1 Dec to 8 Dec is two. Null for bad dates. */
export function programWeeks(startsOn: string, endsOn: string): number | null {
  const a = dayNumber(startsOn);
  const b = dayNumber(endsOn);
  return a === null || b === null || b < a ? null : Math.ceil((b - a + 1) / 7);
}

/**
 * The one check of a program value that the zod shape cannot hold (it needs several fields, or the limits). Returns the reason as a
 * plain sentence, or null when the value is fine. The build_program job uses it as `check` (so the AI is told and retries), and
 * `commands/proposals:accept` runs it again with the limits of that moment.
 */
export function checkProgramValue(value: ProgramValue, limits: Limit[]): string | null {
  const a = dayNumber(value.startsOn);
  const b = dayNumber(value.endsOn);
  if (a === null) return `startsOn: "${value.startsOn}" is not a real date`;
  if (b === null) return `endsOn: "${value.endsOn}" is not a real date`;
  if (b < a) return "endsOn: the program must not end before it starts";
  const weeks = programWeeks(value.startsOn, value.endsOn)!;
  if (weeks > PROGRAM_MAX_WEEKS) return `a program lasts at most ${PROGRAM_MAX_WEEKS} weeks (this one is ${weeks})`;
  let next = 1;
  for (const [i, p] of value.phases.entries()) {
    if (p.weekTo < p.weekFrom) return `phases[${i}]: weekTo must not be before weekFrom`;
    if (p.weekFrom < next) return `phases[${i}]: weeks ${p.weekFrom}..${Math.min(p.weekTo, next - 1)} are already in an earlier phase (phases must be in order and not overlap)`;
    if (p.weekFrom > next) return `phases[${i}]: no phase covers ${next === p.weekFrom - 1 ? `week ${next}` : `weeks ${next}..${p.weekFrom - 1}`} (no gaps between phases)`;
    next = p.weekTo + 1;
  }
  if (next - 1 !== weeks) return `phases cover ${next - 1} weeks but the program has ${weeks} (from ${value.startsOn} to ${value.endsOn}); the phases must cover every week`;
  // A phase may leave a session of the week out (a taper phase has no "B"); a key that no phase has is a mistake.
  const nowhere = value.week.find((k) => !value.phases.some((p) => p.sessions.some((s) => s.key === k)));
  if (nowhere !== undefined) return `week lists "${nowhere}" but no phase has a session with that key`;
  for (const [i, p] of value.phases.entries()) {
    const keys = new Set<string>();
    for (const s of p.sessions) {
      if (keys.has(s.key)) return `phases[${i}]: the session key "${s.key}" is used twice`;
      keys.add(s.key);
    }
    for (const s of p.sessions) {
      const hit = avoidedInPlan({ rationale: "", exercises: s.exercises }, limits);
      if (hit) return `phases[${i}] session "${s.key}": "${hit}" is marked avoid`;
    }
  }
  return null;
}

export type ProgramState = "before" | "running" | "ended";

/** Where the program stands on `today` (a local "YYYY-MM-DD"): before, running or ended; the week (1-based, clamped to 1..weeks); the phase of that week. */
export function programPosition(p: { startsOn: string; endsOn: string; phases: ProgramPhase[] }, today: string): { state: ProgramState; week: number; weeks: number; phaseIndex: number } {
  const weeks = programWeeks(p.startsOn, p.endsOn) ?? 1;
  const start = dayNumber(p.startsOn) ?? 0;
  const t = dayNumber(today) ?? start;
  const end = dayNumber(p.endsOn) ?? start;
  const state: ProgramState = t < start ? "before" : t > end ? "ended" : "running";
  const week = Math.min(weeks, Math.max(1, Math.floor((t - start) / 7) + 1));
  const found = p.phases.findIndex((ph) => ph.weekFrom <= week && week <= ph.weekTo);
  return { state, week, weeks, phaseIndex: found >= 0 ? found : Math.max(0, p.phases.length - 1) };
}

export interface ProgramSlot {
  slot: number;
  key: string;
  title: string;
  done: boolean;
}
export interface ProgramNext {
  slot: number;
  key: string;
  title: string;
  activity: string;
  exercises: PlanExercise[];
  note?: string;
}
export interface ProgramNow {
  state: ProgramState;
  week: number;
  weeks: number;
  phaseIndex: number;
  slots: ProgramSlot[];
  next: ProgramNext | null;
}

/**
 * The "now" block of one program on `today`. Slots are numbered from 1 in the order of `week` (a key may repeat: A, B, A are slots 1, 2, 3).
 * `isDone(week, slot)` says whether a live session carries that link. `fill` puts the kg of the last time into the written session.
 * `next` is the first slot not done, and only while the program runs and is active.
 */
export function programNow(
  p: { startsOn: string; endsOn: string; week: string[]; phases: ProgramPhase[]; status: "active" | "paused" | "done" },
  today: string,
  isDone: (week: number, slot: number) => boolean,
  fill: (s: ProgramSession) => PlanExercise[],
): ProgramNow {
  const pos = programPosition(p, today);
  const phase = p.phases[pos.phaseIndex];
  const sessionOf = (key: string) => phase?.sessions.find((s) => s.key === key);
  // The slots of this week: the keys of `week` that this phase has, numbered by their place in `week`. A phase with none of
  // them (the last days before an event, with sessions of its own) offers its own sessions in the order written.
  const inWeek = p.week.map((key, i) => ({ slot: i + 1, key })).filter((x) => sessionOf(x.key));
  const own = inWeek.length > 0 ? inWeek : (phase?.sessions ?? []).map((s, i) => ({ slot: i + 1, key: s.key }));
  const slots = own.map((x) => ({ ...x, title: sessionOf(x.key)?.title ?? x.key, done: isDone(pos.week, x.slot) }));
  const open = pos.state === "running" && p.status === "active" ? slots.find((s) => !s.done) : undefined;
  const session = open ? sessionOf(open.key) : undefined;
  const next = open && session ? { slot: open.slot, key: open.key, title: session.title, activity: session.activity, exercises: fill(session), ...(session.note ? { note: session.note } : {}) } : null;
  return { ...pos, slots, next };
}

/**
 * Puts the weight of the last time into a written session (plain code, no AI). For an exercise with sets, the kg of the LAST set of the
 * same exercise name (case and outer space ignored) is taken from the last session of this program with the same key (`last`);
 * when that one has no such exercise, from the newest session of the whole log that has it (`log`, newest first); when none has it, the
 * written kg stays. Reps, set count, order, notes, the `max` flag and time exercises stay as written. A named exercise is looked up once.
 */
export function fillKg(written: PlanExercise[], last: { exercises: Exercise[] } | null, log: { exercises: Exercise[] }[]): PlanExercise[] {
  // The kg of every set of the exercise in one session: set 3 of today takes set 3 of last time, so a ramp stays a ramp.
  const lastKg = (ex: Exercise[] | undefined, key: string): number[] | null => {
    const hit = ex?.find((e) => e.measure !== "time" && e.sets.length > 0 && activityKey(e.name) === key);
    if (!hit || hit.measure === "time") return null;
    return hit.sets.map((x) => (x as { kg: number }).kg);
  };
  return written.map((e) => {
    if (e.measure === "time") return e;
    const key = activityKey(e.name);
    let kg = lastKg(last?.exercises, key);
    for (const s of log) {
      if (kg !== null) break;
      kg = lastKg(s.exercises, key);
    }
    if (kg === null) return e;
    const from = kg;
    return { ...e, sets: e.sets.map((s, i) => ({ ...s, kg: from[Math.min(i, from.length - 1)]! })) };
  });
}
