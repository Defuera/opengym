import { z } from "zod";

/** Tracker readings from the phone's health store (ADR-036). Readings, not facts the person logged: they never become sessions. */
export const TRACKER_DAYS_MAX = 31;
export const TRACKER_WORKOUTS_MAX = 100;

const DateSchema = z.string().regex(/^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/, "must be YYYY-MM-DD");
const minutesOfDay = z.number().int().min(0).max(1440);
const bpm = z.number().int().min(20).max(250);
const MS_MAX = 4_102_444_800_000; // 2100-01-01
const DAY_MS = 86_400_000;

/** One calendar day (the phone's local date). A missing field means the phone had no value. Replaces the stored row of that date. */
export const TrackerDaySchema = z.object({
  date: DateSchema,
  sleepMinutes: minutesOfDay.optional(),
  sleepLightMinutes: minutesOfDay.optional(),
  sleepDeepMinutes: minutesOfDay.optional(),
  sleepRemMinutes: minutesOfDay.optional(),
  restingHeartRate: bpm.optional(),
  steps: z.number().int().min(0).max(200_000).optional(),
  activeEnergyKcal: z.number().min(0).max(20_000).optional(),
});
export type TrackerDay = z.infer<typeof TrackerDaySchema>;

/** One workout the tracker wrote to the store. `workoutId` is the store's own id, so a second sync of the same workout changes nothing. */
export const TrackerWorkoutSchema = z
  .object({
    workoutId: z.string().min(1).max(200),
    type: z.string().min(1).max(60),
    startedAt: z.number().int().min(0).max(MS_MAX),
    endedAt: z.number().int().min(0).max(MS_MAX),
    minutes: z.number().int().min(0).max(2880),
    distanceKm: z.number().min(0).max(1000).optional(),
    energyKcal: z.number().min(0).max(20_000).optional(),
    avgHeartRate: bpm.optional(),
    sourceName: z.string().min(1).max(100),
  })
  .refine((w) => w.endedAt >= w.startedAt && w.endedAt - w.startedAt <= 2 * DAY_MS, { message: "endedAt must be after startedAt, at most 48 h" });
export type TrackerWorkout = z.infer<typeof TrackerWorkoutSchema>;

export const TrackerSyncSchema = z.object({
  days: z.array(TrackerDaySchema).max(TRACKER_DAYS_MAX),
  workouts: z.array(TrackerWorkoutSchema).max(TRACKER_WORKOUTS_MAX),
});
