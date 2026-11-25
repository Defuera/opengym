import { describe, expect, it } from "vitest";
import { buildStartInput } from "../functions/model/startInput";
import { pickPlace } from "../functions/model/startSave";

/** ADR-035: a rebuild with feedback keeps the place of the proposal the person saw. */
const GYM = { placeId: "p-gym", name: "Gym" };
const HOME = { placeId: "p-home", name: "Home" };
const PLACES = [GYM, HOME];
const rebuild = (feedback: string[]) => ({ previousPlaceId: "p-gym", feedback });

describe("pickPlace on a rebuild", () => {
  it("keeps the previous place when the model guessed another one from an equipment remark (the 24 Nov trace)", () => {
    expect(pickPlace(PLACES, "Home", "p-home", rebuild(["I do have balance board"]))).toEqual({ place: GYM });
  });
  it("keeps the previous place when the model gave no place, instead of the last used one", () => {
    expect(pickPlace(PLACES, undefined, "p-home", rebuild(["more legs"]))).toEqual({ place: GYM });
  });
  it("takes the other place when the feedback names it, in any case", () => {
    expect(pickPlace(PLACES, "Home", "p-gym", rebuild(["I am at  HOME today"]))).toEqual({ place: HOME });
  });
  it("a new name the feedback does not contain is dropped too", () => {
    expect(pickPlace(PLACES, "Hotel", undefined, rebuild(["shorter"]))).toEqual({ place: GYM });
    expect(pickPlace(PLACES, "Hotel", undefined, rebuild(["I'm at the hotel"]))).toEqual({ newName: "Hotel" });
  });
  it("a first build is as before, and an unknown previous place changes nothing", () => {
    expect(pickPlace(PLACES, "Home", "p-gym")).toEqual({ place: HOME });
    expect(pickPlace(PLACES, "Home", "p-gym", { previousPlaceId: "gone", feedback: ["x"] })).toEqual({ place: HOME });
  });
});

describe("the build_session input on a rebuild", () => {
  const data = { sessions: [], goals: [], context: [], limits: [], entries: [], now: Date.UTC(2026, 10, 25), places: [{ placeId: "p-gym", name: "Gym", text: "" }, { placeId: "p-home", name: "Home", text: "Balance board" }] };
  it("carries the place of the previous proposal as currentPlace", () => {
    const { job } = buildStartInput({ name: "Gym", feedback: ["I do have balance board"], previousPlan: [{ name: "Squat", sets: [] }], previousPlaceId: "p-gym" }, data);
    expect(job.currentPlace).toBe("Gym");
  });
  it("has none on a first build", () => {
    expect(buildStartInput({ name: "Gym", previousPlaceId: "p-gym" }, data).job.currentPlace).toBeUndefined();
  });
});
