import type { BuildCase, Check } from "../types";

const KNEE_MOVES = ["leg extension", "deep squat", "back squat", "front squat", "walking lunge", "bulgarian split squat", "jump squat", "box jump", { re: "\\bsquats?\\b(?<!goblet squats?)", flags: "i" }];
const BASIC: Check[] = [{ kind: "noAvoided" }, { kind: "equipment" }];
const SIZE = (min: number, max = 12): Check => ({ kind: "count", of: "exercises", min, max });

/** The session plan for the known complaints. Each case says what it guards against. */
export const buildCases: BuildCase[] = [
  {
    id: "bs-named-no-note", job: "build_session", family: "named_activity", persona: "jonas",
    about: "A named activity with no note gives a full session at the last place of that activity.",
    name: "Gym", text: "",
    gates: [...BASIC, { kind: "equals", field: "place", value: "Gym" }, { kind: "equals", field: "type", value: "Gym" }],
    expect: [SIZE(4), { kind: "minutes", max: 90 }],
  },
  {
    id: "bs-free-quick-home", job: "build_session", family: "free_request", persona: "mara",
    about: "A free request 'quick session at home, 20 min' means the Home activity, the Home place and about 20 minutes.",
    name: null, text: "quick session at home, 20 min",
    gates: [...BASIC, { kind: "placeMatches", re: "home" }, { kind: "minutes", max: 25 }],
    expect: [SIZE(3), { kind: "contains", field: "planText", any: ["dumbbell", "push up", "bridge", "plank"], why: "uses what Mara has" }],
  },
  {
    id: "bs-home-dumbbells-only", job: "build_session", family: "equipment", persona: "mara",
    about: "A home session where the place has only two dumbbells and a mat: no bottles, barbell, machines, cables or bench.",
    name: "Home", text: "full body today",
    gates: [...BASIC, { kind: "equals", field: "place", value: "Home" }],
    expect: [SIZE(4), { kind: "contains", field: "planText", any: ["dumbbell", "goblet"], why: "uses the dumbbells" }],
  },
  {
    id: "bs-home-nothing", job: "build_session", family: "equipment", persona: "jonas",
    about: "At a home place with nothing, the plan is bodyweight only.",
    name: "Home", text: "no equipment at all today",
    gates: [...BASIC, { kind: "equals", field: "place", value: "Home" }],
    expect: [SIZE(3), { kind: "notContains", field: "planText", any: ["dumbbell", "barbell", "kettlebell", "band", "bench", "machine", "cable"] }],
  },
  {
    id: "bs-knee-legs-day", job: "build_session", family: "limit", persona: "jonas",
    about: "A legs session with a left-knee limit has no movement marked avoid.",
    name: "Gym", text: "legs day",
    gates: [...BASIC, { kind: "notContains", field: "exerciseNames", any: KNEE_MOVES, why: "knee-loaded squat or lunge" }],
    expect: [SIZE(4), { kind: "contains", field: "exerciseNames", any: ["leg curl", "romanian deadlift", "hip thrust", "leg press", "glute", "calf"], why: "legs without the knee" }],
  },
  {
    id: "bs-knee-forbidden-request", job: "build_session", family: "limit", persona: "jonas",
    about: "A request for a movement a limit forbids is not followed, and the person still gets a session.",
    name: "Gym", text: "I want leg extensions and deep squats today",
    gates: [...BASIC, { kind: "notContains", field: "exerciseNames", any: ["leg extension", "deep squat", "back squat"] }],
    expect: [SIZE(3)],
  },
  {
    id: "bs-short-15", job: "build_session", family: "short_time", persona: "mara",
    about: "15 minutes: the plan fits the time and is still a session (not one or two exercises).",
    name: "Home", text: "only 15 minutes today",
    gates: [...BASIC, { kind: "minutes", max: 20 }],
    expect: [SIZE(3, 6)],
  },
  {
    id: "bs-short-20-gym", job: "build_session", family: "short_time", persona: "jonas",
    about: "20 minutes in the gym: fits the time and has at least three exercises (the 'thin session' complaint).",
    name: "Gym", text: "20 min, in a hurry",
    gates: [...BASIC, { kind: "minutes", max: 25 }],
    expect: [SIZE(3, 8)],
  },
  {
    id: "bs-rebuild-no-bottles", job: "build_session", family: "rebuild", persona: "mara",
    about: "After a plan with water bottles, the feedback 'I have no water bottles, I have two 8 kg dumbbells' gives a plan with dumbbells and no bottles.",
    name: "Home", text: "", placeText: { home: "" },
    previousPlan: { rationale: "Full body with what you have.", exercises: [{ name: "Bottle squat", sets: [{ reps: 12, kg: 2 }] }, { name: "Bottle row", sets: [{ reps: 12, kg: 2 }] }, { name: "Bottle shoulder press", sets: [{ reps: 10, kg: 2 }] }, { name: "Plank", measure: "time", sets: [{ minutes: 1 }] }] },
    feedback: ["I have no water bottles, I have two 8 kg dumbbells"],
    gates: [...BASIC, { kind: "notContains", field: "planText", any: ["bottle"] }],
    expect: [{ kind: "contains", field: "planText", any: ["dumbbell", "goblet"], why: "uses the dumbbells" }, SIZE(3)],
  },
  {
    id: "bs-rebuild-two-rounds", job: "build_session", family: "rebuild", persona: "mara",
    about: "A second feedback round keeps the first: still dumbbells and no bottles, and now no jumping.",
    name: "Home", text: "", placeText: { home: "" },
    previousPlan: { rationale: "Full body with your dumbbells.", exercises: [{ name: "Goblet squat", sets: [{ reps: 12, kg: 8 }, { reps: 12, kg: 8 }] }, { name: "Dumbbell row", sets: [{ reps: 10, kg: 8 }] }, { name: "Jumping jack", sets: [{ reps: 30, kg: 0 }] }, { name: "Burpee", sets: [{ reps: 10, kg: 0 }] }] },
    feedback: ["I have no water bottles, I have two 8 kg dumbbells", "No jumping please, the neighbours live below"],
    gates: [...BASIC, { kind: "notContains", field: "planText", any: ["bottle", "jump", "burpee", "skipping", "hop"] }],
    expect: [{ kind: "contains", field: "planText", any: ["dumbbell", "goblet"], why: "still uses the dumbbells" }, SIZE(3)],
  },
  {
    id: "bs-place-hotel", job: "build_session", family: "place", persona: "jonas",
    about: "A note that says 'hotel gym' names a new place, not the last place of the activity.",
    name: "Gym", text: "hotel gym this week",
    gates: [{ kind: "noAvoided" }, { kind: "placeMatches", re: "hotel" }],
    expect: [SIZE(3)],
  },
  {
    id: "bs-place-home-note", job: "build_session", family: "place", persona: "jonas",
    about: "A note that says 'at home' puts the session at the Home place, and the plan fits a place with nothing.",
    name: "Gym", text: "at home today, nothing here",
    gates: [...BASIC, { kind: "equals", field: "place", value: "Home" }],
    expect: [SIZE(3)],
  },
  {
    id: "bs-name-kept", job: "build_session", family: "named_activity", persona: "mara",
    about: "A fixed activity name that is new to the log is kept exactly. The raw answer is also checked (warning).",
    name: "Evening Strength", text: "",
    gates: [...BASIC, { kind: "equals", field: "type", value: "Evening Strength" }],
    expect: [SIZE(3)],
    warn: [{ kind: "equals", field: "type", value: "Evening Strength" }, { kind: "contains", field: "rawType", all: ["Evening Strength"], why: "the model changed the name" }],
  },
  {
    id: "bs-empty-history", job: "build_session", family: "empty_history", persona: "nia",
    about: "A new user with no history gets a plain, short starter session and no claim about past sessions.",
    name: "Gym", text: "first time ever",
    gates: [{ kind: "count", of: "exercises", min: 1, max: 12 }, { kind: "noAvoided" }],
    expect: [SIZE(3, 8), { kind: "notContains", field: "planText", any: [{ re: "last time|as before|your usual|you did", flags: "i" }] }],
  },
];
