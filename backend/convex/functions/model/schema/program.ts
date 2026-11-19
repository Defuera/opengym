import { z } from "zod";
import { PlanExerciseSchema } from "./plan";

const DateSchema = z.string().regex(/^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/, "must be YYYY-MM-DD");

export const ProgramSessionSchema = z.object({
  key: z.string().min(1).max(12),
  title: z.string().min(1).max(40),
  activity: z.string().min(1).max(40),
  exercises: z.array(PlanExerciseSchema).min(1).max(14),
  note: z.string().max(200).optional(),
});

export const ProgramPhaseSchema = z.object({
  title: z.string().min(1).max(40),
  weekFrom: z.number().int().min(1),
  weekTo: z.number().int().min(1),
  note: z.string().max(400),
  sessions: z.array(ProgramSessionSchema).min(1).max(8),
});

/** What the coach proposes: the whole program. The rules that need more than one field are in model/program.ts (checkProgramValue). */
export const ProgramValueSchema = z.object({
  title: z.string().min(1).max(60),
  purpose: z.string().max(300),
  startsOn: DateSchema,
  endsOn: DateSchema,
  week: z.array(z.string().min(1).max(12)).min(1).max(10),
  phases: z.array(ProgramPhaseSchema).min(1).max(8),
  rules: z.array(z.string().max(300)).max(12),
  tests: z.array(z.string().max(200)).max(12),
});

/**
 * The short form the coach writes an exercise in ("3 x 10 at 20 kg" as {sets: 3, reps: 10, kg: 20}; a hold or a ride as
 * {sets: 3, minutes: 0.5}). Code makes the full sets from it. Reason: a whole program with one object per set was too long
 * for the model to write inside the time limit (measured 2026-11-19: over 65 s per attempt). The full form is still accepted.
 */
const expandExercise = (e: unknown): unknown => {
  if (!e || typeof e !== "object" || typeof (e as { sets?: unknown }).sets !== "number") return e;
  const x = e as { name?: unknown; sets: number; reps?: unknown; kg?: unknown; max?: unknown; minutes?: unknown; note?: unknown };
  const n = Math.min(10, Math.max(1, Math.round(x.sets)));
  const note = typeof x.note === "string" && x.note ? { note: x.note } : {};
  if (typeof x.minutes === "number") return { name: x.name, measure: "time", sets: Array.from({ length: n }, () => ({ minutes: x.minutes })), ...note };
  return { name: x.name, sets: Array.from({ length: n }, () => ({ reps: x.reps, kg: typeof x.kg === "number" ? x.kg : 0, max: x.max === true })), ...note };
};
const BuildSessionSchema = ProgramSessionSchema.extend({ exercises: z.array(z.preprocess(expandExercise, PlanExerciseSchema)).min(1).max(14) });
const BuildPhaseSchema = ProgramPhaseSchema.extend({ sessions: z.array(BuildSessionSchema).min(1).max(8) });

/** What the build_program job returns: the program and the one line the person reads. */
export const ProgramBuildSchema = ProgramValueSchema.extend({ phases: z.array(BuildPhaseSchema).min(1).max(8), reason: z.string().max(200) }) as unknown as z.ZodType<z.infer<typeof ProgramValueSchema> & { reason: string }>;

export type ProgramSession = z.infer<typeof ProgramSessionSchema>;
export type ProgramPhase = z.infer<typeof ProgramPhaseSchema>;
export type ProgramValue = z.infer<typeof ProgramValueSchema>;
export type ProgramBuild = z.infer<typeof ProgramBuildSchema>;
