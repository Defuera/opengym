import { v } from "convex/values";

/** One day of tracker readings (ADR-036). Keyed by the phone's local date. */
export const trackerDayFields = {
  date: v.string(),
  sleepMinutes: v.optional(v.number()),
  sleepLightMinutes: v.optional(v.number()),
  sleepDeepMinutes: v.optional(v.number()),
  sleepRemMinutes: v.optional(v.number()),
  restingHeartRate: v.optional(v.number()),
  steps: v.optional(v.number()),
  activeEnergyKcal: v.optional(v.number()),
};

/** One workout of the phone's health store (ADR-036). Keyed by the store's own id. */
export const trackerWorkoutFields = {
  workoutId: v.string(),
  type: v.string(),
  startedAt: v.number(),
  endedAt: v.number(),
  minutes: v.number(),
  distanceKm: v.optional(v.number()),
  energyKcal: v.optional(v.number()),
  avgHeartRate: v.optional(v.number()),
  sourceName: v.string(),
};
