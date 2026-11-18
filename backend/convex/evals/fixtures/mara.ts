import type { Persona } from "../types";
import { activity, ex, goal, gym, note, timeEx } from "./build";

const HOME = "pl-mara-home";
const PARK = "pl-mara-park";

/** Everything below is invented. Mara is a beginner who trains at home with two 8 kg dumbbells and a mat. */
export const mara: Persona = {
  id: "mara",
  about: "Beginner at home with two 8 kg dumbbells and a mat. Two sessions a week. No limits.",
  places: [
    {
      placeId: HOME,
      name: "Home",
      text: "Two 8 kg dumbbells and a yoga mat. Nothing else.",
      has: ["dumbbell", "mat", "bodyweight"],
      lacks: ["bottle", "barbell", "machine", "cable", "bench", "rack", "pull-up bar", "pull up bar", "kettlebell", "smith", "lat pulldown", "leg press", "band", "trx"],
    },
    {
      placeId: PARK,
      name: "Park",
      text: "Open grass and one pull-up bar on a frame.",
      has: ["pull-up bar", "pull up bar", "bodyweight"],
      lacks: ["dumbbell", "barbell", "machine", "cable", "bench", "kettlebell", "mat"],
    },
  ],
  sessions: [
    gym("m-01", 26, "Home", "Full body", HOME, 35, [ex("Goblet squat", [10, 8], [10, 8], [10, 8]), ex("Dumbbell row", [10, 8], [10, 8]), ex("Push-up", [6, 0], [5, 0]), timeEx("Plank", 1)]),
    activity("m-02", 25, "Walk", 35, 2.5),
    gym("m-03", 23, "Home", "Full body", HOME, 35, [ex("Goblet squat", [10, 8], [10, 8], [10, 8]), ex("Glute bridge", [15, 0], [15, 0]), ex("Dumbbell shoulder press", [8, 6], [8, 6]), ex("Push-up", [6, 0], [6, 0])]),
    gym("m-04", 19, "Home", "Full body", HOME, 40, [ex("Goblet squat", [12, 8], [12, 8], [12, 8]), ex("Dumbbell row", [10, 8], [10, 8], [10, 8]), ex("Dumbbell Romanian deadlift", [10, 8], [10, 8]), timeEx("Plank", 1)]),
    gym("m-05", 16, "Home", "Full body", HOME, 40, [ex("Goblet squat", [12, 8], [12, 8], [12, 8]), ex("Push-up", [8, 0], [7, 0], [6, 0]), ex("Dumbbell shoulder press", [8, 8], [8, 8]), ex("Glute bridge", [15, 0], [15, 0])]),
    gym("m-06", 12, "Home", "Full body", HOME, 40, [ex("Dumbbell row", [12, 8], [12, 8], [10, 8]), ex("Dumbbell Romanian deadlift", [12, 8], [12, 8]), ex("Biceps curl", [10, 8], [10, 8]), timeEx("Plank", 1)]),
    gym("m-07", 9, "Home", "Full body", HOME, 40, [ex("Goblet squat", [12, 8], [12, 8], [12, 8]), ex("Push-up", [8, 0], [8, 0], [6, 0]), ex("Dumbbell row", [12, 8], [12, 8]), ex("Glute bridge", [15, 0], [15, 0], [15, 0])]),
    activity("m-08", 7, "Walk", 40, 3),
    gym("m-09", 5, "Home", "Full body", HOME, 45, [ex("Goblet squat", [12, 8], [12, 8], [12, 8]), ex("Dumbbell shoulder press", [10, 8], [8, 8], [8, 8]), ex("Dumbbell Romanian deadlift", [12, 8], [12, 8]), timeEx("Plank", 1)]),
    gym("m-10", 2, "Home", "Full body", HOME, 45, [ex("Push-up", [8, 0], [8, 0], [7, 0]), ex("Dumbbell row", [12, 8], [12, 8], [12, 8]), ex("Goblet squat", [12, 8], [12, 8]), ex("Biceps curl", [10, 8], [10, 8])]),
  ],
  goals: [
    goal("mg-1", 28, { title: "Do 10 push-ups on my toes", kind: "custom" }),
    goal("mg-2", 28, { title: "Train at home twice a week", kind: "consistency", sessionsPerWeek: 2 }),
  ],
  limits: [],
  context: [note("mc-1", 28, "background", "Started training in October. Trains at home in the evening, usually 35 to 45 minutes.")],
  entries: [],
};
