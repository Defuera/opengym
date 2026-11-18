import { describe, expect, it } from "vitest";
import { loadForPlan } from "../functions/model/rules/load";

describe("loadForPlan", () => {
  it("marks the muscles of the planned exercises and leaves the rest at 0", () => {
    const m = loadForPlan([{ name: "Bench Press", sets: 3, minutes: 0 }]);
    expect(m.chest).toBe(3);
    expect(m.calves).toBe(0);
  });
  it("an empty plan loads nothing", () => {
    expect(Object.values(loadForPlan([])).every((x) => x === 0)).toBe(true);
  });
});
