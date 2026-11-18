import type { ParseCase } from "../types";

/** One text each. The activity is the one the user chose; the text is word for word what they wrote. */
export const parseCases: ParseCase[] = [
  {
    id: "pl-minutes-km", job: "parse_log", family: "numbers", persona: "jonas", about: "Minutes and kilometres are read as written.",
    activity: "Run", text: "45 min, 8 km, easy pace",
    gates: [{ kind: "noInvented" }, { kind: "parsedValue", field: "minutes", equals: 45 }, { kind: "parsedValue", field: "distanceKm", equals: 8 }],
    expect: [{ kind: "parsedDay", daysAgo: 0 }],
  },
  {
    id: "pl-one-hour", job: "parse_log", family: "numbers", persona: "jonas", about: "'1h easy' is 60 minutes.",
    activity: "Run", text: "1h easy",
    gates: [{ kind: "noInvented" }, { kind: "parsedValue", field: "minutes", equals: 60 }, { kind: "parsedValue", field: "distanceKm", absent: true }],
    expect: [],
  },
  {
    id: "pl-yesterday", job: "parse_log", family: "date", persona: "jonas", about: "'yesterday' moves the session to the day before today.",
    activity: "Walk", text: "yesterday, 30 min",
    gates: [{ kind: "noInvented" }, { kind: "parsedValue", field: "minutes", equals: 30 }, { kind: "parsedDay", daysAgo: 1 }],
    expect: [],
  },
  {
    id: "pl-exercise-no-sets", job: "parse_log", family: "exercises", persona: "jonas", about: "An exercise named without sets means the usual sets of the log; no number is made up.",
    activity: "Gym", text: "did bench press",
    gates: [{ kind: "noInvented" }],
    expect: [{ kind: "contains", field: "exerciseNames", any: ["bench press"] }],
  },
  {
    id: "pl-no-numbers", job: "parse_log", family: "nothing_invented", persona: "jonas", about: "A text with no numbers gives no minutes, no distance and no exercises.",
    activity: "Run", text: "felt great today, legs were heavy but the weather was lovely",
    gates: [{ kind: "noInvented" }, { kind: "parsedNothing" }],
    expect: [{ kind: "parsedDay", daysAgo: 0 }],
  },
  {
    id: "pl-mixed-language", job: "parse_log", family: "language", persona: "jonas", about: "A text in German and English is read: 30 minutes, 5 km.",
    activity: "Run", text: "30 Minuten gelaufen, 5 km, easy und locker",
    gates: [{ kind: "noInvented" }, { kind: "parsedValue", field: "minutes", equals: 30 }, { kind: "parsedValue", field: "distanceKm", equals: 5 }],
    expect: [],
  },
];
