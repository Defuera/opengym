import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "../functions/_generated/api";
import { MUSCLE_KEYS } from "../functions/model/rules/muscles";
import { TOKEN, pushSession, setup, settle, type T } from "./helpers";

let t: T;
const end = Date.UTC(2026, 10, 17, 12);
beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(end);
  t = setup();
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

const save = (s: object) => t.mutation(api.commands.sessions.save, { token: TOKEN, session: s as ReturnType<typeof pushSession> });
const load = (sessionId: string) => t.query(api.queries.sessions.load, { token: TOKEN, sessionId });

describe("queries/sessions:load", () => {
  it("returns a level 0..3 for every muscle key, for this session only", async () => {
    await save(pushSession("a", end - 86_400_000)); // an older session must not count
    await save({ ...pushSession("b", end), exercises: [{ name: "Leg Press", sets: [{ reps: 8, kg: 100, max: false }, { reps: 8, kg: 100, max: false }] }] });
    const m = (await load("b"))!;
    expect(Object.keys(m).sort()).toEqual([...MUSCLE_KEYS].sort());
    expect(m.quads).toBe(3); // 2 sets: the busiest muscle
    expect(m.glutes).toBe(2); // secondary: half weight, share 0.5
    expect(m.chest).toBe(0); // the older bench session is not in this one
    await settle(t);
  });

  it("uses the same level rule as About me", async () => {
    await save(pushSession("a", end - 1000));
    await settle(t);
    const about = await t.query(api.queries.aboutMe.get, { token: TOKEN });
    expect(await load("a")).toEqual(about.load.d14); // a single session in the window: same levels
  });

  it("a time exercise loads by minutes, an activity by its table, an empty session by nothing", async () => {
    await save({ ...pushSession("c", end), exercises: [{ name: "Bike", measure: "time", sets: [{ minutes: 20 }] }] });
    const c = (await load("c"))!;
    expect(c.quads).toBe(3);
    expect(c.chest).toBe(0);
    await save({ sessionId: "r", kind: "activity", type: "Run", startedAt: end - 1000, endedAt: end, minutes: 30, exercises: [], source: "app" });
    expect((await load("r"))!.calves).toBe(3);
    await save({ sessionId: "w", kind: "activity", type: "Walk", startedAt: end - 1000, endedAt: end, minutes: 30, exercises: [], source: "app" });
    expect(Object.values((await load("w"))!).every((x) => x === 0)).toBe(true);
    await settle(t);
  });

  it("is null for an unknown session and needs the token", async () => {
    expect(await load("nope")).toBeNull();
    await expect(t.query(api.queries.sessions.load, { token: "bad", sessionId: "a" })).rejects.toThrow(/unauthorized/);
  });
});
