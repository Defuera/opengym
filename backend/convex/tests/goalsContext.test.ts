import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "../functions/_generated/api";
import { TOKEN, setup, settle, type T } from "./helpers";

let t: T;
beforeEach(() => {
  vi.useFakeTimers();
  t = setup();
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

describe("goals", () => {
  it("creates, updates, lists and removes; create is idempotent", async () => {
    const make = { token: TOKEN, goalId: "g1", title: "Bench 80", kind: "strength" as const, exercise: "Bench press", targetKg: 80 };
    await t.mutation(api.commands.goals.create, make);
    await t.mutation(api.commands.goals.create, { ...make, title: "ignored on resend" });
    const goals = await t.query(api.queries.goals.list, { token: TOKEN });
    expect(goals).toHaveLength(1);
    expect(goals[0]).toMatchObject({ goalId: "g1", title: "Bench 80", status: "active", source: "user", targetKg: 80 });

    await t.mutation(api.commands.goals.update, { token: TOKEN, goalId: "g1", status: "done", targetKg: 90 });
    expect((await t.query(api.queries.goals.list, { token: TOKEN }))[0]).toMatchObject({ status: "done", targetKg: 90, title: "Bench 80" });

    expect(await t.mutation(api.commands.goals.remove, { token: TOKEN, goalId: "g1" })).toBe(true);
    expect(await t.mutation(api.commands.goals.remove, { token: TOKEN, goalId: "g1" })).toBe(false);
    expect(await t.query(api.queries.goals.list, { token: TOKEN })).toEqual([]);
    await settle(t);
  });

  it("validates input and reports a missing goal", async () => {
    const ok = { token: TOKEN, goalId: "g", title: "x", kind: "custom" as const };
    await expect(t.mutation(api.commands.goals.create, { ...ok, title: "" })).rejects.toThrow(/title/);
    await expect(t.mutation(api.commands.goals.create, { ...ok, title: "x".repeat(81) })).rejects.toThrow(/title/);
    await expect(t.mutation(api.commands.goals.create, { ...ok, sessionsPerWeek: 15 })).rejects.toThrow(/sessionsPerWeek/);
    await expect(t.mutation(api.commands.goals.create, { ...ok, targetKg: 1001 })).rejects.toThrow(/targetKg/);
    await expect(t.mutation(api.commands.goals.update, { token: TOKEN, goalId: "nope", status: "done" })).rejects.toThrow(/not found/);
    expect(await t.query(api.queries.goals.list, { token: TOKEN })).toEqual([]);
  });

  it("a goal change asks for a rebuild and keeps the stored read models", async () => {
    await t.mutation(api.commands.goals.create, { token: TOKEN, goalId: "g1", title: "Train 3x", kind: "consistency", sessionsPerWeek: 3 });
    await settle(t);
    expect(await t.run((ctx) => ctx.db.query("plans").collect())).toHaveLength(3);
    expect(await t.run((ctx) => ctx.db.query("dashboards").collect())).toHaveLength(2);
    // The goal shows in the stored dashboard layout after the rebuild; before it, the rules layout has it too.
    const d = await t.query(api.queries.dashboard.get, { token: TOKEN, days: 7 });
    expect(d.stored).toBe(true);
    expect(d.dashboard.modules.some((m) => m.type === "goal_progress")).toBe(true);
    // A change keeps the stored rows until the next rebuild replaces them.
    await t.mutation(api.commands.goals.update, { token: TOKEN, goalId: "g1", status: "done" });
    expect(await t.run((ctx) => ctx.db.query("plans").collect())).toHaveLength(3);
    expect((await t.query(api.queries.plans.next, { token: TOKEN, focus: "Push" })).stored).toBe(true);
    await settle(t);
  });
});

describe("context items", () => {
  it("creates, updates, lists and removes; create is idempotent", async () => {
    const make = { token: TOKEN, itemId: "c1", text: "Go lighter on squats", topic: "legs" };
    await t.mutation(api.commands.context.create, make);
    await t.mutation(api.commands.context.create, make);
    const items = await t.query(api.queries.context.list, { token: TOKEN });
    expect(items).toHaveLength(1);
    expect(items[0]).toMatchObject({ itemId: "c1", active: true, source: "user" });
    await t.mutation(api.commands.context.update, { token: TOKEN, itemId: "c1", active: false, text: "Skip squats" });
    expect((await t.query(api.queries.context.list, { token: TOKEN }))[0]).toMatchObject({ active: false, text: "Skip squats" });
    expect(await t.mutation(api.commands.context.remove, { token: TOKEN, itemId: "c1" })).toBe(true);
    expect(await t.query(api.queries.context.list, { token: TOKEN })).toEqual([]);
    await settle(t);
  });

  it("validates input and reports a missing item", async () => {
    await expect(t.mutation(api.commands.context.create, { token: TOKEN, itemId: "c", text: "", topic: "x" })).rejects.toThrow(/text/);
    await expect(t.mutation(api.commands.context.create, { token: TOKEN, itemId: "c", text: "a", topic: "x".repeat(31) })).rejects.toThrow(/topic/);
    await expect(t.mutation(api.commands.context.update, { token: TOKEN, itemId: "nope", active: false })).rejects.toThrow(/not found/);
  });
});
