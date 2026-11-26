import { z } from "zod";
import { IdSchema, MsSchema, SessionSourceSchema } from "./common";

export const SetEntrySchema = z.object({
  reps: z.number().int().min(0).max(100),
  kg: z.number().min(0).max(500),
  max: z.boolean(),
  /** One more rep was tried after `reps` and not completed. */
  failed: z.boolean().optional(),
  at: z.number().optional(),
});

/** One entry of a time exercise (a bike, a hold): minutes, and optionally the distance. No reps, no kg. */
export const TimeEntrySchema = z
  .object({
    minutes: z.number().gt(0).max(600),
    distanceKm: z.number().nonnegative().optional(),
    note: z.string().max(200).optional(),
    at: z.number().optional(),
  })
  .strict();

/** What the person wrote about an exercise in this session (ADR-029): how it went that day. Their own words. */
export const EXERCISE_COMMENT_MAX = 1000;
const ExerciseCommentSchema = z.string().min(1).max(EXERCISE_COMMENT_MAX).optional();

/** One set of the plan as it was when the exercise entered the session (ADR-041): reps and kg, or minutes. Not a fact of the log. */
export const PlannedSetSchema = z.union([
  z.object({ reps: z.number().int().min(0).max(100), kg: z.number().min(0).max(500), max: z.boolean() }).strict(),
  z.object({ minutes: z.number().gt(0).max(600), distanceKm: z.number().nonnegative().optional() }).strict(),
]);
export const PLAN_NOTE_MAX = 400;
const PlannedFields = {
  /** The sets of the plan when the exercise entered the session. Absent: the exercise had no plan. */
  planned: z.array(PlannedSetSchema).max(30).optional(),
  /** The coach's note of the exercise in the plan. */
  planNote: z.string().max(PLAN_NOTE_MAX).optional(),
};

/** A planned exercise that was removed, or left with no done set. */
export const SkippedExerciseSchema = z.object({ name: z.string().min(1).max(60), measure: z.literal("time").optional(), planned: z.array(PlannedSetSchema).max(30) });

/** An exercise measured in sets and reps. `measure` is absent in all stored data: absent means "sets". */
export const SetsExerciseSchema = z.object({
  name: z.string().min(1).max(60),
  measure: z.literal("sets").optional(),
  // Strict: minutes/distanceKm must not appear on a sets entry, so a mixed exercise is rejected.
  sets: z.array(SetEntrySchema.strict()).max(12),
  comment: ExerciseCommentSchema,
  ...PlannedFields,
});

/** An exercise measured in time. Usually one entry; more are allowed (intervals). */
export const TimeExerciseSchema = z.object({
  name: z.string().min(1).max(60),
  measure: z.literal("time"),
  sets: z.array(TimeEntrySchema).max(12),
  comment: ExerciseCommentSchema,
  ...PlannedFields,
});

export const ExerciseSchema = z.union([SetsExerciseSchema, TimeExerciseSchema]);

export const SessionSchema = z
  .object({
    id: IdSchema,
    kind: z.enum(["gym", "activity"]),
    /** The activity name: any text 1..40. For kind gym (a session with sets) "Gym", "Home", ...; for kind activity "Run", "Bouldering", ... */
    type: z.string().min(1).max(40),
    /** The flavour of this session ("Upper", "Legs", "Easy", ...). A label; the AI advises it, the app writes it. */
    focus: z.string().min(1).max(40).optional(),
    startedAt: MsSchema,
    endedAt: MsSchema,
    exercises: z.array(ExerciseSchema).max(15),
    minutes: z.number().int().nonnegative().optional(),
    distanceKm: z.number().nonnegative().optional(),
    note: z.string().optional(),
    source: SessionSourceSchema,
    importId: z.string().optional(),
    /** Where the session happened (ADR-021). Not known when absent. */
    placeId: z.string().min(1).max(100).optional(),
    /** The program this session belongs to and where in it (written by the app). */
    programId: z.string().min(1).max(100).optional(),
    programWeek: z.number().int().min(1).optional(),
    programSlot: z.number().int().min(1).optional(),
    programKey: z.string().min(1).max(12).optional(),
    /** The plan this session started from (ADR-041): the coach's reason, and the planned exercises that were removed or left with no done set. Absent: no plan. */
    planNote: z.string().max(PLAN_NOTE_MAX).optional(),
    skipped: z.array(SkippedExerciseSchema).max(30).optional(),
  })
  .refine((s) => s.type.trim().length > 0, { message: "type must not be blank", path: ["type"] })
  .refine((s) => s.kind === "gym" || s.exercises.length === 0, {
    message: "activity sessions must have no exercises",
    path: ["exercises"],
  })
  .refine((s) => s.endedAt >= s.startedAt, {
    message: "endedAt must not be before startedAt",
    path: ["endedAt"],
  });

export type SetEntry = z.infer<typeof SetEntrySchema>;
export type TimeEntry = z.infer<typeof TimeEntrySchema>;
export type SetsExercise = z.infer<typeof SetsExerciseSchema>;
export type TimeExercise = z.infer<typeof TimeExerciseSchema>;
export type Exercise = SetsExercise | TimeExercise;

/** True when the exercise is measured in minutes. Absent `measure` means sets and reps. */
export const isTimeExercise = (e: { measure?: "sets" | "time" }): boolean => e.measure === "time";

/** The sets-and-reps entries of an exercise; empty for a time exercise. */
export const repEntries = (e: Exercise): SetsExercise["sets"] => (e.measure === "time" ? [] : e.sets);

/** The time entries of an exercise; empty for an exercise with sets. */
export const timeEntries = (e: Exercise): TimeEntry[] => (e.measure === "time" ? e.sets : []);

/** The heaviest kg of an exercise; time entries are ignored (0 when there is no weight). */
export const topKg = (e: Exercise): number => Math.max(0, ...repEntries(e).map((x) => x.kg));

/** Total minutes of a time exercise; 0 for an exercise with sets. */
export const totalMinutes = (e: Exercise): number => timeEntries(e).reduce((n, x) => n + x.minutes, 0);
export type Session = z.infer<typeof SessionSchema>;

/** What `commands/sessions:logText` takes: the activity name, the user's text (kept word for word) and the time it is about (ADR-018). */
export const LogTextInputSchema = z.object({
  type: z.string().trim().min(1).max(40),
  text: z.string().min(1).max(1000).refine((t) => t.trim().length > 0, { message: "text must not be blank" }),
  at: MsSchema,
});
export type LogTextInput = z.infer<typeof LogTextInputSchema>;
