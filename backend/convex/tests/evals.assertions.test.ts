// @vitest-environment node
import { describe, expect, it } from "vitest";
import { evaluate, implicitGates } from "../evals/assertions";
import { claimsItem, lackedIn } from "../evals/assertions/equipment";
import { allowedNumbers } from "../evals/assertions/parse";
import type { BuildSubject, ChatSubject, LearnSubject, ParseSubject } from "../evals/assertions/subject";
import { matches, overlap } from "../evals/assertions/text";
import { NOW, persona, placeOf } from "../evals/fixtures";
import type { Check } from "../evals/types";
import type { StartProposal } from "../functions/model/schema";

const jonas = persona("jonas");
const mara = persona("mara");
const exs = (...names: string[]) => names.map((name) => ({ name, sets: [{ reps: 10, kg: 0, max: false }, { reps: 10, kg: 0, max: false }] }));
const build = (names: string[], o: { persona?: typeof mara; place?: string | null; minutes?: number; type?: string; rawType?: string } = {}): BuildSubject => {
  const p = o.persona ?? mara;
  const placeName = o.place === undefined ? "Home" : o.place;
  const proposal: StartProposal = { kind: "gym", type: o.type ?? "Home", ...(o.minutes ? { minutes: o.minutes } : {}), plan: { rationale: "r", exercises: exs(...names) } };
  return { job: "build_session", persona: p, limits: p.limits, placeName, place: placeName ? placeOf(p, placeName) : null, proposal, rawType: o.rawType ?? proposal.type };
};
const pass = (c: Check, s: Parameters<typeof evaluate>[1]) => evaluate(c, s).pass;

describe("text matching", () => {
  it("a keyword is a whole word, plural and hyphens are fine", () => {
    expect(matches("Leg extensions", "leg extension")).toBe(true);
    expect(matches("Pull-up bar hang", "pull up bar")).toBe(true);
    expect(matches("Bottle squat", "bottle")).toBe(true);
    expect(matches("Bandit squat", "band")).toBe(false);
    expect(matches("Dumbbell row", "bell")).toBe(false);
    expect(matches("Goblet squat", { re: "gob" })).toBe(true);
  });
  it("overlap is the share of 4-word runs found again", () => {
    const a = "you should rest your knee for two days and see a doctor if it persists";
    expect(overlap(a, a)).toBe(1);
    expect(overlap("a completely different answer about sets of leg curls", a)).toBe(0);
    expect(overlap("too short", a)).toBe(0);
  });
});

describe("build_session checks", () => {
  it("noAvoided: the real rule code and the phrase match both catch a movement", () => {
    expect(pass({ kind: "noAvoided" }, build(["Romanian deadlift", "Leg curl"], { persona: jonas, place: "Gym" }))).toBe(true);
    expect(pass({ kind: "noAvoided" }, build(["Leg extension"], { persona: jonas, place: "Gym" }))).toBe(false);
    const plural = evaluate({ kind: "noAvoided" }, build(["Leg extensions"], { persona: jonas, place: "Gym" })); // the exact-name rule misses the plural
    expect(plural.pass).toBe(false);
    expect(plural.reason).toContain("Leg extensions");
  });
  it("equipment: names and notes against the lacks list of the place", () => {
    expect(pass({ kind: "equipment" }, build(["Goblet squat", "Dumbbell row", "Push-up"]))).toBe(true);
    for (const bad of ["Bottle squat", "Barbell row", "Cable fly", "Dumbbell bench press", "Leg press machine"]) expect(pass({ kind: "equipment" }, build([bad])), bad).toBe(false);
    expect(pass({ kind: "equipment" }, build(["Push-up"], { place: null }))).toBe(false);
  });
  it("count and minutes", () => {
    expect(pass({ kind: "count", of: "exercises", min: 3 }, build(["a", "b", "c"]))).toBe(true);
    expect(pass({ kind: "count", of: "exercises", min: 3 }, build(["a", "b"]))).toBe(false);
    expect(pass({ kind: "count", of: "exercises", max: 2 }, build(["a", "b", "c"]))).toBe(false);
    expect(pass({ kind: "minutes", max: 20 }, build(["a", "b", "c"]))).toBe(true); // 6 sets = 12 min
    expect(pass({ kind: "minutes", max: 10 }, build(["a", "b", "c"]))).toBe(false);
    expect(pass({ kind: "minutes", max: 20 }, build(["a"], { minutes: 45 }))).toBe(false);
  });
  it("equals and placeMatches", () => {
    expect(pass({ kind: "equals", field: "type", value: "Home" }, build(["a"]))).toBe(true);
    expect(pass({ kind: "equals", field: "type", value: "Gym" }, build(["a"]))).toBe(false);
    expect(pass({ kind: "equals", field: "place", value: "home" }, build(["a"]))).toBe(true);
    expect(pass({ kind: "equals", field: "place", value: "Gym" }, build(["a"], { place: null }))).toBe(false);
    expect(pass({ kind: "placeMatches", re: "hotel" }, { ...build(["a"]), placeName: "Hotel gym" })).toBe(true);
    expect(pass({ kind: "placeMatches", re: "hotel" }, build(["a"]))).toBe(false);
  });
  it("contains and notContains read names, plan text and the raw type", () => {
    const s = build(["Goblet squat", "Dumbbell row"], { rawType: "Evening Strength" });
    expect(pass({ kind: "contains", field: "planText", any: ["dumbbell"] }, s)).toBe(true);
    expect(pass({ kind: "contains", field: "planText", all: ["dumbbell", "goblet"] }, s)).toBe(true);
    expect(pass({ kind: "contains", field: "planText", all: ["dumbbell", "barbell"] }, s)).toBe(false);
    expect(pass({ kind: "notContains", field: "exerciseNames", any: ["bottle"] }, s)).toBe(true);
    expect(pass({ kind: "notContains", field: "exerciseNames", any: ["dumbbell"] }, s)).toBe(false);
    expect(pass({ kind: "contains", field: "rawType", all: ["Evening Strength"] }, s)).toBe(true);
    expect(evaluate({ kind: "contains", field: "planText", any: ["barbell"], why: "needs a bar" }, s).reason).toContain("barbell");
  });
  it("a check for another job fails clearly", () => {
    expect(evaluate({ kind: "noteUnchanged" }, build(["a"])).reason).toContain("does not apply");
  });
  it("implicit gates: valid output and the model answered", () => {
    const ok = implicitGates(build(["a", "b"]), ["ai"]);
    expect(ok.every((g) => g.pass)).toBe(true);
    const fb = implicitGates(build(["a"]), ["ai", "fallback"]);
    expect(fb.find((g) => g.name === "model_answered")!.pass).toBe(false);
    expect(implicitGates({ ...build(["a"]), proposal: null }, ["fallback"]).find((g) => g.name === "valid_output")!.pass).toBe(false);
  });
});

const chat = (...answers: string[]): ChatSubject => ({ job: "chat", persona: mara, turns: answers.map((assistant, i) => ({ user: `m${i}`, assistant })) });

describe("chat checks", () => {
  it("contains: the answer names the triceps", () => {
    expect(pass({ kind: "contains", field: "answer", any: ["triceps"] }, chat("That is the triceps brachii."))).toBe(true);
    expect(pass({ kind: "contains", field: "answer", any: ["triceps"] }, chat("That is the biceps."))).toBe(false);
  });
  it("answerHead is the first 200 characters", () => {
    const late = `${"x ".repeat(120)}12 sets`;
    expect(pass({ kind: "contains", field: "answerHead", any: [{ re: "\\d" }] }, chat(late))).toBe(false);
    expect(pass({ kind: "contains", field: "answerHead", any: [{ re: "\\d" }] }, chat("Do 3 sets of 10."))).toBe(true);
  });
  it("mustNotRepeat: the declined advice must not come back", () => {
    const c: Check = { kind: "mustNotRepeat", any: [{ re: "\\brest\\b", flags: "i" }, "see a doctor"] };
    expect(pass(c, chat("You should rest and see a doctor.", "Do 3 sets of leg curls, light."))).toBe(true);
    const bad = evaluate(c, chat("You should rest.", "Fine, but please rest a day between."));
    expect(bad.pass).toBe(false);
    expect(bad.reason).toContain("earlier answer said it");
  });
  it("similarity: a long copied stretch fails the warning", () => {
    const first = "Keep the load light and stop the set when the knee feels tight on the way down.";
    expect(pass({ kind: "similarity", max: 0.3 }, chat(first, first))).toBe(false);
    expect(pass({ kind: "similarity", max: 0.3 }, chat(first, "Three sets of twelve leg curls at a weight you can control."))).toBe(true);
  });
});

const parse = (text: string, parsed: object | null, found: ParseSubject["found"], day = "2026-11-18"): ParseSubject => ({ job: "parse_log", text, parsed: parsed as ParseSubject["parsed"], found, day, now: NOW });

describe("parse_log checks", () => {
  const good = parse("45 min, 8 km, easy pace", { minutes: 45, distanceKm: 8, focus: "Easy" }, { minutes: 45, distanceKm: 8, focus: "Easy" });
  it("parsedValue: equals and absent", () => {
    expect(pass({ kind: "parsedValue", field: "minutes", equals: 45 }, good)).toBe(true);
    expect(pass({ kind: "parsedValue", field: "minutes", equals: 40 }, good)).toBe(false);
    expect(pass({ kind: "parsedValue", field: "distanceKm", absent: true }, good)).toBe(false);
    expect(pass({ kind: "parsedValue", field: "distanceKm", equals: 8 }, parse("x", {}, {}))).toBe(false);
  });
  it("parsedDay: yesterday is the day before the fixed today", () => {
    expect(pass({ kind: "parsedDay", daysAgo: 1 }, parse("yesterday", {}, {}, "2026-11-17"))).toBe(true);
    expect(pass({ kind: "parsedDay", daysAgo: 1 }, parse("yesterday", {}, {}, "2026-11-18"))).toBe(false);
  });
  it("noInvented: a number the text does not give fails; 1h is 60", () => {
    expect(pass({ kind: "noInvented" }, good)).toBe(true);
    expect(pass({ kind: "noInvented" }, parse("1h easy", { minutes: 60 }, { minutes: 60 }))).toBe(true);
    expect(pass({ kind: "noInvented" }, parse("felt good", { minutes: 30 }, { minutes: 30 }))).toBe(false);
    expect(pass({ kind: "noInvented" }, parse("did bench", { exercises: [{ name: "Bench press", sets: [{ reps: 8, kg: 60 }] }] }, {}))).toBe(false);
    expect([...allowedNumbers("1h30 and 8,5 km")].sort()).toEqual([1, 8.5, 30, 90].sort());
  });
  it("parsedNothing: any minutes, distance or exercise fails", () => {
    expect(pass({ kind: "parsedNothing" }, parse("felt good", {}, { focus: "Easy" }))).toBe(true);
    expect(pass({ kind: "parsedNothing" }, parse("felt good", {}, { minutes: 30 }))).toBe(false);
    expect(pass({ kind: "parsedNothing" }, parse("felt good", {}, { exercises: [{ name: "x" }] }))).toBe(false);
  });
  it("exerciseNames reads the saved exercises", () => {
    expect(pass({ kind: "contains", field: "exerciseNames", any: ["bench press"] }, parse("did bench press", {}, { exercises: [{ name: "Bench press" }] }))).toBe(true);
  });
});

const learn = (start: string, ...after: string[]): LearnSubject => ({ job: "learn_place", startNote: start, steps: after.map((a, i) => ({ sentence: `s${i}`, before: i === 0 ? start : after[i - 1]!, after: a })) });

describe("learn_place checks", () => {
  const start = "Two 8 kg dumbbells and a yoga mat. Nothing else.";
  it("noteUnchanged and noteChanged", () => {
    expect(pass({ kind: "noteUnchanged" }, learn(start, start, start))).toBe(true);
    expect(pass({ kind: "noteUnchanged" }, learn(start, start, `${start} A bench.`))).toBe(false);
    expect(pass({ kind: "noteChanged" }, learn(start, `${start} A bench.`))).toBe(true);
    expect(pass({ kind: "noteChanged" }, learn(start, start))).toBe(false);
  });
  it("claims: a clause with the item and no negation says it is there", () => {
    expect(claimsItem("Two dumbbells and a mat. No bench.", "bench")).toBe(false);
    expect(claimsItem("Two dumbbells and a mat. No bench.", "mat")).toBe(true);
    expect(claimsItem("A band, a bench", "bench")).toBe(true);
    expect(pass({ kind: "claims", item: "mat", value: false }, learn(start, "Two 8 kg dumbbells. The mat is gone."))).toBe(true);
    expect(pass({ kind: "claims", item: "mat", value: false }, learn(start, `${start} The mat is gone.`))).toBe(false);
    expect(pass({ kind: "claims", item: "band", value: true }, learn(start, `${start} A resistance band.`))).toBe(true);
  });
  it("lackedIn lists the keywords found", () => {
    expect(lackedIn("Bottle squat", placeOf(mara, "Home"))).toEqual(['"bottle"']);
  });
});
