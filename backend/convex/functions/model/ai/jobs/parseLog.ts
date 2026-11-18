import { z } from "zod";
import type { JobDef } from "../runJob";
import { dataPrompt, systemPrompt } from "../promptRules";
import { type Exercise, type Session, isTimeExercise } from "../../schema";
import { appTimeZone, shiftToDay } from "../../logDate";
import { activityKey } from "../../sessionShape";

/**
 * parse_log: reads the structure out of the text a user wrote about one thing they did (minutes, distance, a short focus,
 * the day, and exercises when the text describes work with sets). ADR-018, same pattern as parse_goal.
 *
 * ADR-002: the text is the fact and is stored first, word for word, in the note. This job only fills the structure of that
 * session from the user's own words; it never creates a session and never changes the note or the activity name.
 * ADR-004 pipeline: prompt, provider, JSON, zod, one retry, plain code fallback.
 */
export interface KnownExercise {
  name: string;
  /** The sets of the last time, as a prompt carries them: "6x40, 8x60" or "25 min". */
  lastSets: string;
  measure?: "time";
}

export interface ParseLogInput {
  /** The activity name the user chose. Fixed. */
  activity: string;
  /** What the user wrote (max 1000). */
  text: string;
  /** Today in the owner's time zone: "2026-11-18 (Wednesday)". */
  today: string;
  /** Every exercise of the log with its last sets, most recent first. */
  exercisesTheUserKnows: KnownExercise[];
}

const opt = <T extends z.ZodType>(s: T) => s.nullish().transform((v) => v ?? undefined);

const RepSetSchema = z.object({ reps: z.number().int().min(0).max(100), kg: z.number().min(0).max(500) });
const TimeSetSchema = z.object({ minutes: z.number().gt(0).max(600), distanceKm: opt(z.number().nonnegative().max(1000)) });

export const ParsedLogSchema = z.object({
  minutes: opt(z.number().gt(0).max(600)),
  distanceKm: opt(z.number().nonnegative().max(1000)),
  focus: opt(z.string().trim().min(1).max(40)),
  date: opt(z.string().regex(/^\d{4}-\d{2}-\d{2}$/)),
  exercises: opt(
    z
      .array(
        z.object({
          name: z.string().trim().min(1).max(60),
          measure: opt(z.enum(["sets", "time"])),
          sets: opt(z.array(z.union([TimeSetSchema, RepSetSchema])).max(12)),
        }),
      )
      .max(15),
  ),
});
export type ParsedLog = z.infer<typeof ParsedLogSchema>;

// ---------- plain-code reading (the fallback) ----------

const NUM = String.raw`(\d+(?:[.,]\d+)?)`;
const num = (s: string) => Number(s.replace(",", "."));
const MIN_UNIT = String.raw`(?:minutes?|mins?)(?![a-z])`;

/** Minutes: "45 min", "1h", "1.5 hours", "1h30", "1h 30 min", "1:10" (hours:minutes). Null when the text holds none. */
export function readMinutes(text: string): number | null {
  const hours = new RegExp(`${NUM}\\s*(hours?|hrs?|h)(?![a-z])`, "i").exec(text);
  let total: number | null = null;
  if (hours) {
    total = num(hours[1]!) * 60;
    const rest = text.slice(hours.index + hours[0].length);
    const spaced = new RegExp(`^\\s*(\\d{1,2})\\s*${MIN_UNIT}`, "i").exec(rest);
    const stuck = hours[2]!.toLowerCase() === "h" ? /^(\d{2})(?![\d.,]|\s*(?:km|kg))/.exec(rest) : null; // "1h30"
    const extra = spaced ?? stuck;
    if (extra) total += Number(extra[1]);
  } else {
    const mins = new RegExp(`${NUM}\\s*${MIN_UNIT}`, "i").exec(text);
    if (mins) total = num(mins[1]!);
  }
  if (total === null) {
    const clock = /(?<![\d:@])(?<!\bat )(\d{1,2}):([0-5]\d)(?![\d:])/i.exec(text);
    if (clock) total = Number(clock[1]) * 60 + Number(clock[2]);
  }
  if (total === null) return null;
  const m = Math.round(total);
  return m >= 1 && m <= 600 ? m : null;
}

/** Distance: "8 km", "8,5km", "10 kilometres". Null when the text holds none. */
export function readKm(text: string): number | null {
  const km = new RegExp(`${NUM}\\s*(?:km|kilomet(?:er|re)s?)(?![a-z])`, "i").exec(text);
  const v = km ? num(km[1]!) : null;
  return v !== null && v > 0 && v <= 1000 ? v : null;
}

/** Plain-code reading: minutes and kilometres, nothing else. */
export function parseLogFallback(text: string): ParsedLog {
  const minutes = readMinutes(text);
  const distanceKm = readKm(text);
  return { ...(minutes !== null ? { minutes } : {}), ...(distanceKm !== null ? { distanceKm } : {}) } as ParsedLog;
}

// ---------- plain-code finishing (runs after the AI answer too) ----------

/** The last time each exercise of the log was done with sets (most recent session wins), by activityKey. Gym sessions only. */
export function usualSets(all: Session[]): Map<string, Exercise> {
  const out = new Map<string, Exercise>();
  for (const s of all) {
    if (s.kind !== "gym") continue;
    for (const e of s.exercises) if (e.sets.length > 0) out.set(activityKey(e.name), e);
  }
  return out;
}

const copySets = (e: Exercise): Exercise =>
  isTimeExercise(e)
    ? ({ name: e.name, measure: "time", sets: (e.sets as { minutes: number; distanceKm?: number }[]).map((x) => ({ minutes: x.minutes, ...(x.distanceKm !== undefined ? { distanceKm: x.distanceKm } : {}) })) } as Exercise)
    : ({ name: e.name, sets: (e.sets as { reps: number; kg: number }[]).map((x) => ({ reps: x.reps, kg: x.kg, max: false })) } as Exercise);

/**
 * Turns the exercises the AI returned into stored ones. A name of the log takes the log's spelling. An exercise with no sets
 * gets the sets of the last time it was logged ("reported without sets = the usual sets"); one that is not in the log and has
 * no sets is left out (it stays in the note). Entries of the wrong kind for the exercise are dropped. At most 15 exercises.
 */
export function finalizeLogExercises(given: NonNullable<ParsedLog["exercises"]>, usual: Map<string, Exercise>): Exercise[] {
  const out: Exercise[] = [];
  const seen = new Set<string>();
  for (const g of given) {
    const key = activityKey(g.name);
    if (seen.has(key)) continue;
    const known = usual.get(key);
    const time = (g.sets ?? []).filter((x): x is z.infer<typeof TimeSetSchema> => "minutes" in x);
    const reps = (g.sets ?? []).filter((x): x is z.infer<typeof RepSetSchema> => "reps" in x);
    const isTime = g.measure === "time" || (g.measure === undefined && time.length > 0 && reps.length === 0);
    const name = known?.name ?? g.name;
    let e: Exercise | null = null;
    if (isTime && time.length > 0) {
      e = { name, measure: "time", sets: time.map((x) => ({ minutes: x.minutes, ...(x.distanceKm !== undefined ? { distanceKm: x.distanceKm } : {}) })) };
    } else if (!isTime && reps.length > 0) {
      e = { name, sets: reps.map((x) => ({ reps: x.reps, kg: x.kg, max: false })) };
    } else if (known) {
      e = { ...copySets(known), name };
    }
    if (!e) continue;
    seen.add(key);
    out.push(e);
    if (out.length >= 15) break;
  }
  return out;
}

/** What the save step takes: the structure found, with the day applied, the exercises finished and the minutes rounded. */
export function structureOf(parsed: ParsedLog, usual: Map<string, Exercise>, at: number, now: number) {
  const exercises = finalizeLogExercises(parsed.exercises ?? [], usual);
  const startedAt = parsed.date ? shiftToDay(at, parsed.date, now, appTimeZone()) : at;
  return {
    ...(startedAt !== at ? { startedAt, endedAt: startedAt } : {}),
    ...(parsed.focus !== undefined ? { focus: parsed.focus } : {}),
    ...(parsed.minutes !== undefined ? { minutes: Math.max(1, Math.round(parsed.minutes)) } : {}),
    ...(parsed.distanceKm !== undefined ? { distanceKm: parsed.distanceKm } : {}),
    ...(exercises.length > 0 ? { exercises } : {}),
  };
}

const ROLE = `You read what a person wrote about one thing they did, and you fill in its structure. You know which activity it was (activity), what they wrote (text), today's date and weekday (today), and every exercise they have logged before with its last sets (exercisesTheUserKnows).

Three things are fixed. Use only what the text says: never invent a number, a name or a set that it does not give. You read the text; you never change it, and the name of the activity is not yours to change. When the text names a day ("yesterday", "on Monday"), give that day as date (YYYY-MM-DD, never after today); when it names none, leave date out.

minutes and distanceKm describe the whole activity; focus is its flavour in one or two words when the text says one (Easy, Intervals). Give exercises only when the text describes work with sets. An exercise takes its name from exercisesTheUserKnows when the text means one of them, and keeps the person's own words otherwise. Work measured in time inside such a session (a bike, a plank) is an exercise with measure "time" and minutes. When the text names an exercise without reps and weights, give only its name: it means the usual sets, and the code fills them in.`;

const SHAPE = `{"minutes"?: number, "distanceKm"?: number, "focus"?: string (max 40), "date"?: "YYYY-MM-DD", "exercises"?: [{"name": string (max 60), "measure"?: "time", "sets"?: [{"reps": int, "kg": number} | {"minutes": number, "distanceKm"?: number}]}]}  // leave out what the text does not say; at most 15 exercises, at most 12 sets each`;

export const parseLogJob: JobDef<ParseLogInput, ParsedLog> = {
  name: "parse_log",
  description: "The structure of a logged text: minutes, distance, focus, the day and, when it has sets, the exercises. Only what the text says.",
  fallbackDescription: "Minutes (45 min, 1h, 1:10) and kilometres (8 km) read with a regex; nothing else.",
  json: true,
  maxTokens: 1500,
  output: ParsedLogSchema as unknown as z.ZodType<ParsedLog>,
  build: (i) => ({
    system: systemPrompt("parse_log", ROLE, SHAPE),
    messages: [{ role: "user", content: dataPrompt("Read this log.", { activity: i.activity, text: i.text, today: i.today, exercisesTheUserKnows: i.exercisesTheUserKnows }) }],
  }),
  fallback: (i) => parseLogFallback(i.text),
};
