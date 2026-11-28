import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "../functions/_generated/api";
import { coachTracker } from "../functions/lib/trackerDb";
import { coachPicture } from "../functions/model/ai/jobs/coachPicture";
import { buildPlanInput } from "../functions/model/ai/jobs/inputs";
import { planSessionJob } from "../functions/model/ai/jobs/planSession";
import { assembleCoachContext } from "../functions/model/coachContext";
import { NO_TRACKER_DATA_FACT, trackerForPrompt } from "../functions/model/trackerForCoach";
import { TOKEN, pushSession, setup, type T } from "./helpers";

const NOW = Date.UTC(2026, 10, 25, 12, 0);
const H = 3_600_000;
const day = (date: string, extra = {}) => ({ date, ...extra });
const workout = (workoutId: string, startedAt: number, minutes = 45, extra = {}) => ({
  workoutId,
  type: "Running",
  startedAt,
  endedAt: startedAt + minutes * 60_000,
  minutes,
  sourceName: "Fitbit",
  ...extra,
});
const sync = (t: T, days: object[], workouts: object[], token = TOKEN) => t.mutation(api.commands.tracker.sync, { token, days: days as never, workouts: workouts as never });
const rows = (t: T) => t.run(async (c) => ({ days: await c.db.query("trackerDays").collect(), workouts: await c.db.query("trackerWorkouts").collect(), sessions: await c.db.query("sessions").collect() }));

describe("tracker sync", () => {
  let t: T;
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(NOW);
    t = setup();
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllEnvs();
  });

  it("needs the token", async () => {
    await expect(sync(t, [], [], "x")).rejects.toThrow(/unauthorized/);
  });

  it("stores days and workouts, never sessions", async () => {
    const r = await sync(t, [day("2026-11-24", { sleepMinutes: 440, restingHeartRate: 52, steps: 8000, activeEnergyKcal: 500 })], [workout("w1", NOW - 30 * H)]);
    expect(r).toEqual({ days: 1, workouts: 1, written: 2 });
    const s = await rows(t);
    expect(s.days).toHaveLength(1);
    expect(s.workouts).toHaveLength(1);
    expect(s.sessions).toHaveLength(0);
  });

  it("is idempotent: the same batch twice writes nothing the second time", async () => {
    const days = [day("2026-11-24", { steps: 8000 })];
    const workouts = [workout("w1", NOW - 30 * H)];
    await sync(t, days, workouts);
    vi.setSystemTime(NOW + 1000);
    const again = await sync(t, days, workouts);
    expect(again.written).toBe(0);
    const s = await rows(t);
    expect(s.days).toHaveLength(1);
    expect(s.workouts).toHaveLength(1);
    expect(s.days[0]!.updatedAt).toBe(NOW);
  });

  it("a changed day replaces the row of that date; a duplicate date in one batch keeps the last", async () => {
    await sync(t, [day("2026-11-24", { steps: 100, sleepMinutes: 400 })], []);
    await sync(t, [day("2026-11-24", { steps: 200 }), day("2026-11-24", { steps: 300 })], []);
    const s = await rows(t);
    expect(s.days).toHaveLength(1);
    expect(s.days[0]!.steps).toBe(300);
    expect(s.days[0]!.sleepMinutes).toBeUndefined();
  });

  it("caps the batch size", async () => {
    const many = Array.from({ length: 32 }, (_, i) => day(`2026-10-${String(i + 1).padStart(2, "0")}`, { steps: 1 }));
    await expect(sync(t, many, [])).rejects.toThrow(/tracker\.days/);
    const ws = Array.from({ length: 101 }, (_, i) => workout(`w${i}`, NOW - i * H));
    await expect(sync(t, [], ws)).rejects.toThrow(/tracker\.workouts/);
  });

  it("rejects values out of range and bad dates", async () => {
    await expect(sync(t, [day("2026-11-24", { restingHeartRate: 400 })], [])).rejects.toThrow(/restingHeartRate/);
    await expect(sync(t, [day("2026-11-24", { sleepMinutes: 2000 })], [])).rejects.toThrow(/sleepMinutes/);
    await expect(sync(t, [day("24/11/2026", { steps: 1 })], [])).rejects.toThrow(/date/);
    await expect(sync(t, [], [workout("w1", NOW, 45, { distanceKm: 5000 })])).rejects.toThrow(/distanceKm/);
    await expect(sync(t, [], [{ ...workout("w1", NOW), endedAt: NOW - 1 }])).rejects.toThrow(/endedAt/);
    expect((await rows(t)).workouts).toHaveLength(0);
  });
});

describe("tracker block for the coach", () => {
  const session = (id: string, endedAt: number) => ({ ...pushSession(id, endedAt), id, exercises: [] }) as never;

  it("lists the last 7 days with missing values left out, and only those days", () => {
    const block = trackerForPrompt(
      {
        days: [
          day("2026-11-24", { sleepMinutes: 440, sleepDeepMinutes: 70, restingHeartRate: 52, steps: 8000, activeEnergyKcal: 512.4 }),
          day("2026-11-23", { steps: 3000 }),
          day("2026-11-10", { steps: 9 }),
          day("2026-11-22", {}),
        ],
        workouts: [],
      },
      [],
      NOW,
    )!;
    expect(block.last7Days).toEqual(["2026-11-23: steps 3000", "2026-11-24: sleep 7.3 h (deep 1.2), resting heart rate 52, steps 8000, active 512 kcal"]);
    expect(block.workoutsLast14Days).toEqual([]);
  });

  it("lists tracker workouts of 14 days; a workout that overlaps a logged session is not listed, its numbers go on that session", () => {
    const sessionEnd = NOW - 20 * H;
    const logged = pushSession("s1", sessionEnd);
    const block = trackerForPrompt(
      {
        days: [],
        workouts: [
          workout("same", logged.startedAt + 5 * 60_000, 50, { avgHeartRate: 121, energyKcal: 340.2 }),
          workout("run", NOW - 30 * H, 45, { distanceKm: 6.24, avgHeartRate: 148 }),
          workout("old", NOW - 15 * 24 * H),
          workout("bare", sessionEnd + 3 * H, 30),
        ],
      },
      [logged as never],
      NOW,
    )!;
    expect(block.workoutsLast14Days).toHaveLength(2);
    expect(block.workoutsLast14Days[0]).toContain("Running, 45 min, 6.2 km, avg heart rate 148");
    expect(block.workoutsLast14Days[1]).toContain("Running, 30 min");
    expect(block.onLoggedSessions).toEqual(["2026-11-24 Gym Push: tracker saw avg heart rate 121, 340 kcal"]);
  });

  it("an overlapping workout with no numbers is just dropped; no data gives no block", () => {
    const logged = pushSession("s1", NOW - 5 * H);
    expect(trackerForPrompt({ days: [], workouts: [workout("same", logged.startedAt, 60)] }, [logged as never], NOW)).toBeNull();
    expect(trackerForPrompt(undefined, [], NOW)).toBeNull();
    expect(trackerForPrompt({ days: [], workouts: [] }, [session("a", NOW)], NOW)).toBeNull();
  });

  it("a workout that ends after the moment asked is left out", () => {
    expect(trackerForPrompt({ days: [], workouts: [workout("future", NOW - 10 * 60_000, 45)] }, [], NOW)).toBeNull();
  });

  it("reaches coachPicture, the plan input and the chat context, and the prompts say how to use it", () => {
    const tracker = { days: [day("2026-11-24", { steps: 8000 })], workouts: [workout("run", NOW - 30 * H, 45)] };
    const picture = coachPicture([], [], [], [], [], NOW, tracker);
    expect(picture.trackerFromThePhone?.last7Days).toEqual(["2026-11-24: steps 8000"]);
    expect(coachPicture([], [], [], [], [], NOW).trackerFromThePhone).toBeUndefined();

    const plan = buildPlanInput([], [], [], "Gym", undefined, [], tracker, NOW);
    const req = planSessionJob.build(plan);
    expect(req.system).toContain("tracker data from the person's phone");
    expect(req.messages[0]!.content).toContain("trackerFromThePhone");
    expect(planSessionJob.build(buildPlanInput([], [], [], "Gym", undefined, [])).messages[0]!.content).not.toContain("trackerFromThePhone");

    const ctx = assembleCoachContext({ otherThreads: [], sessions: [], goals: [], context: [], tracker, now: NOW }, [], false);
    expect(ctx.contextBlock).toContain("trackerFromThePhone");
    expect(ctx.sources).toContain("tracker");
    expect(ctx.contextBlock).not.toContain(NO_TRACKER_DATA_FACT);
  });

  it("with no tracker data the chat context carries the plain fact about what the app can receive", () => {
    for (const tracker of [undefined, { days: [], workouts: [] }]) {
      const ctx = assembleCoachContext({ otherThreads: [], sessions: [], goals: [], context: [], tracker, now: NOW }, [], false);
      expect(ctx.contextBlock).toContain(NO_TRACKER_DATA_FACT);
      expect(ctx.contextBlock).toContain("Settings > Trackers");
      expect(ctx.contextBlock).toContain("never gets live heart rate");
      expect(ctx.sources).not.toContain("tracker");
    }
  });

  it("coachTracker reads only the last 7 days and 14 days of workouts", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(NOW);
    const t = setup();
    await t.mutation(api.commands.tracker.sync, {
      token: TOKEN,
      days: [day("2026-11-24", { steps: 1 }), day("2026-11-01", { steps: 2 })],
      workouts: [workout("a", NOW - 2 * H), workout("b", NOW - 20 * 24 * H)],
    } as never);
    const got = await t.run((c) => coachTracker(c, "owner", NOW));
    expect(got.days.map((d) => d.date)).toEqual(["2026-11-24"]);
    expect(got.workouts.map((w) => w.workoutId)).toEqual(["a"]);
    expect(got.days[0]).not.toHaveProperty("updatedAt");
    vi.useRealTimers();
  });
});
