import type { Doc } from "../_generated/dataModel";
import type { DatabaseReader } from "../_generated/server";
import { localDate } from "../model/program";
import type { TrackerDay, TrackerWorkout } from "../model/schema";
import { TRACKER_PROMPT_DAYS, TRACKER_PROMPT_WORKOUT_DAYS, type TrackerForCoach } from "../model/trackerForCoach";

const DAY = 86_400_000;
const WORKOUT_SCAN = 80;

type Reader = { db: DatabaseReader };

const strip = <T extends { _id: unknown; _creationTime: number; updatedAt: number }>(d: T) => {
  const { _id, _creationTime, updatedAt, ...rest } = d;
  void _id;
  void _creationTime;
  void updatedAt;
  return rest;
};

/**
 * What the coach reads of the phone's tracker (ADR-036): the day rows of the last 7 days and the workouts of the last 14, as of `now`
 * (a workout that ends after `now` is left out). Bounded. Never the person's sessions: those come from the log.
 */
export async function coachTracker(ctx: Reader, userId: string, now: number, timeZone?: string): Promise<TrackerForCoach> {
  const from = localDate(now - (TRACKER_PROMPT_DAYS - 1) * DAY, timeZone);
  const to = localDate(now, timeZone);
  const days = await ctx.db.query("trackerDays").withIndex("by_user_and_date", (q) => q.eq("userId", userId).gte("date", from).lte("date", to)).collect();
  const workouts = await ctx.db
    .query("trackerWorkouts")
    .withIndex("by_user_and_startedAt", (q) => q.eq("userId", userId).gte("startedAt", now - TRACKER_PROMPT_WORKOUT_DAYS * DAY).lte("startedAt", now))
    .order("desc")
    .take(WORKOUT_SCAN);
  return { days: days.map((d: Doc<"trackerDays">) => strip(d) as TrackerDay), workouts: workouts.map((w: Doc<"trackerWorkouts">) => strip(w) as TrackerWorkout) };
}
