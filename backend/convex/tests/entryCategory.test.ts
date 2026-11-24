import { describe, expect, it } from "vitest";
import { categoryLabel, normaliseCategory, usedCategories } from "../functions/model/entryCategory";

describe("entry categories (ADR-031)", () => {
  it("tidies a label: trim, one space, Title case, at most 24 characters", () => {
    expect(normaliseCategory("  sleep   log ")).toBe("Sleep Log");
    expect(normaliseCategory("x".repeat(40))).toHaveLength(24);
    expect(normaliseCategory("   ")).toBe("other");
  });

  it("matches a known label without regard to case, and the known spelling wins", () => {
    expect(normaliseCategory("MEAL", ["Meal", "Walk"])).toBe("Meal");
    expect(normaliseCategory("walk", ["Meal", "Walk"])).toBe("Walk");
    expect(normaliseCategory("swim", ["Meal"])).toBe("Swim");
  });

  it("reads the old values: Title case, and no label for other", () => {
    expect(categoryLabel("meal")).toBe("Meal");
    expect(categoryLabel("training")).toBe("Training");
    expect(categoryLabel("other")).toBeNull();
    expect(categoryLabel(undefined)).toBeNull();
    expect(categoryLabel("Sleep")).toBe("Sleep");
  });

  it("lists the categories in use, most used first, old and new spellings as one", () => {
    expect(usedCategories(["meal", "Meal", "Sleep", "other", undefined, "walk", "Sleep", "MEAL"])).toEqual(["Meal", "Sleep", "walk"]);
  });
});
