import type { Limit } from "../../functions/model/schema";
import type { Persona } from "../types";
import { activity, ex, goal, gym, note } from "./build";

const GYM = "pl-jonas-gym";

export const jonasKnee: Limit = {
  limitId: "lim-jonas-knee",
  part: "left_knee",
  title: "Left knee",
  status: "active",
  since: "2026-10",
  rules: [
    { kind: "avoid", text: "No leg extension and no deep loaded knee bends", exercises: ["Leg extension", "Deep squat", "Back squat", "Front squat", "Walking lunge", "Bulgarian split squat", "Jump squat", "Box jump"] },
    { kind: "light", text: "Keep the leg press light", exercises: ["Leg press"] },
    { kind: "do", text: "Prefer hip hinge and hamstring work", exercises: ["Romanian deadlift", "Leg curl", "Hip thrust"] },
  ],
};

/** Everything below is invented. Jonas lifts in a gym, has a left-knee limit and a ski trip with a date. */
export const jonas: Persona = {
  id: "jonas",
  about: "Gym lifter, three sessions a week. Left knee: leg extension and deep loaded knee bends are marked avoid. Ski trip on 2027-01-16.",
  places: [
    {
      placeId: GYM,
      name: "Gym",
      text: "Commercial gym: barbells, a power rack, a flat bench, dumbbells up to 40 kg, a cable stack, a lat pulldown, a leg press, a leg curl machine, a treadmill. No Olympic platform.",
      has: ["barbell", "rack", "bench", "dumbbell", "cable", "lat pulldown", "leg press", "leg curl", "treadmill"],
      lacks: ["platform", "sled", "trap bar", "landmine", "battle rope", "rowing machine"],
    },
    {
      placeId: "pl-jonas-home",
      name: "Home",
      text: "Nothing here. Floor space only.",
      has: [],
      lacks: ["dumbbell", "barbell", "kettlebell", "bench", "machine", "cable", "rack", "band", "bottle", "pull-up bar", "pull up bar", "rower", "treadmill", "leg press", "lat pulldown"],
    },
  ],
  sessions: [
    gym("j-01", 27, "Gym", "Upper", GYM, 65, [ex("Bench press", [5, 80], [5, 80], [5, 80], [5, 80]), ex("Lat pulldown", [10, 60], [10, 60], [8, 65]), ex("Shoulder press", [8, 40], [8, 40], [8, 40]), ex("Biceps curl", [10, 16], [10, 16])]),
    gym("j-02", 25, "Gym", "Lower", GYM, 60, [ex("Romanian deadlift", [8, 90], [8, 90], [8, 90]), ex("Leg curl", [12, 45], [12, 45], [12, 45]), ex("Leg press", [12, 100], [12, 100], [12, 100]), ex("Hip thrust", [10, 80], [10, 80], [10, 80])]),
    activity("j-03", 22, "Run", 35, 6, "Easy"),
    gym("j-04", 20, "Gym", "Upper", GYM, 65, [ex("Bench press", [5, 82.5], [5, 82.5], [5, 82.5], [4, 82.5]), ex("Dumbbell row", [10, 32], [10, 32], [10, 32]), ex("Shoulder press", [8, 42.5], [8, 42.5], [7, 42.5]), ex("Triceps pushdown", [12, 30], [12, 30])]),
    gym("j-05", 18, "Gym", "Lower", GYM, 60, [ex("Romanian deadlift", [8, 92.5], [8, 92.5], [8, 92.5]), ex("Leg curl", [12, 47.5], [12, 47.5], [10, 47.5]), ex("Hip thrust", [10, 85], [10, 85], [10, 85]), ex("Calf raise", [15, 60], [15, 60], [15, 60])]),
    gym("j-06", 15, "Gym", "Upper", GYM, 65, [ex("Bench press", [5, 82.5], [5, 82.5], [5, 82.5], [5, 82.5]), ex("Lat pulldown", [10, 62.5], [10, 62.5], [9, 62.5]), ex("Shoulder press", [8, 42.5], [8, 42.5], [8, 42.5]), ex("Biceps curl", [10, 17], [10, 17])]),
    gym("j-07", 13, "Gym", "Lower", GYM, 60, [ex("Romanian deadlift", [8, 95], [8, 95], [8, 95]), ex("Leg press", [12, 100], [12, 100], [12, 100]), ex("Leg curl", [12, 50], [12, 50], [12, 50]), ex("Hip thrust", [10, 90], [10, 90])]),
    activity("j-08", 11, "Run", 40, 7, "Easy"),
    gym("j-09", 8, "Gym", "Upper", GYM, 65, [ex("Bench press", [5, 85], [5, 85], [5, 85], [4, 85]), ex("Dumbbell row", [10, 34], [10, 34], [10, 34]), ex("Shoulder press", [8, 42.5], [8, 42.5], [8, 42.5]), ex("Triceps pushdown", [12, 32.5], [12, 32.5])]),
    gym("j-10", 6, "Gym", "Lower", GYM, 60, [ex("Romanian deadlift", [8, 95], [8, 95], [8, 95]), ex("Leg curl", [12, 50], [12, 50], [12, 50]), ex("Hip thrust", [10, 90], [10, 90], [10, 90]), ex("Calf raise", [15, 65], [15, 65], [15, 65])]),
    gym("j-11", 3, "Gym", "Upper", GYM, 65, [ex("Bench press", [5, 85], [5, 85], [5, 85], [5, 85]), ex("Lat pulldown", [10, 65], [10, 65], [10, 65]), ex("Shoulder press", [8, 45], [8, 45], [7, 45]), ex("Biceps curl", [10, 17], [10, 17])]),
    gym("j-12", 1, "Gym", "Lower", GYM, 60, [ex("Romanian deadlift", [8, 97.5], [8, 97.5], [8, 97.5]), ex("Leg press", [12, 100], [12, 100], [12, 100]), ex("Leg curl", [12, 52.5], [12, 52.5], [12, 52.5]), ex("Hip thrust", [10, 90], [10, 90], [10, 90])]),
  ],
  goals: [
    goal("jg-1", 40, { title: "Be fit for the ski trip on 2027-01-16: strong legs and no knee pain", kind: "custom" }),
    goal("jg-2", 40, { title: "Bench press 100 kg", kind: "strength", exercise: "Bench press", targetKg: 100 }),
    goal("jg-3", 40, { title: "Train three times a week", kind: "consistency", sessionsPerWeek: 3 }),
  ],
  limits: [jonasKnee],
  context: [note("jc-1", 40, "schedule", "Trains after work, about 60 minutes."), note("jc-2", 40, "preference", "Prefers free weights over machines when possible.")],
  entries: [],
};
