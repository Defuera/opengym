import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../functions/_generated/api";
import { timezoneOf } from "../functions/model/timezone";
import { userTimezone } from "../functions/lib/timezoneDb";
import { TOKEN, TOKEN_B, USER_A, USER_B, setupTwo } from "./multiUser";
import { settle, type T } from "./helpers";

/** ADR-039: the time zone of a user (`users.timezone`), else the deployment's APP_TIMEZONE, else UTC. */
let t: T;
const NOW = Date.UTC(2026, 10, 19, 23, 30); // 19 Nov 23:30 UTC = 20 Nov 12:30 in Auckland
beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
  t = setupTwo();
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

describe("timezoneOf", () => {
  it("takes the user's zone first, then APP_TIMEZONE, then UTC", () => {
    expect(timezoneOf()).toBe("UTC");
    expect(timezoneOf(null)).toBe("UTC");
    expect(timezoneOf({})).toBe("UTC");
    vi.stubEnv("APP_TIMEZONE", "Europe/Berlin");
    expect(timezoneOf()).toBe("Europe/Berlin");
    expect(timezoneOf({ timezone: "Pacific/Auckland" })).toBe("Pacific/Auckland");
    expect(timezoneOf({ timezone: "" })).toBe("Europe/Berlin");
  });

  it("userTimezone reads the users row; a user with no row or no zone gets the deployment's", async () => {
    vi.stubEnv("APP_TIMEZONE", "Europe/Berlin");
    await t.run(async (c) => {
      await c.db.insert("users", { userId: USER_A, createdAt: NOW, timezone: "Pacific/Auckland" });
      await c.db.insert("users", { userId: USER_B, createdAt: NOW });
    });
    expect(await t.run((c) => userTimezone(c, USER_A))).toBe("Pacific/Auckland");
    expect(await t.run((c) => userTimezone(c, USER_B))).toBe("Europe/Berlin");
    expect(await t.run((c) => userTimezone(c, "nobody"))).toBe("Europe/Berlin");
  });
});

describe("two users, two zones, one program", () => {
  const program = {
    title: "Knee", purpose: "x", startsOn: "2026-11-20", endsOn: "2026-12-03", week: ["A"],
    phases: [{ title: "Base", weekFrom: 1, weekTo: 2, note: "", sessions: [{ key: "A", title: "A", activity: "Gym", exercises: [{ name: "Row", sets: [{ reps: 8, kg: 30, max: false }] }] }] }],
    rules: [], tests: [],
  };
  const make = (userId: string) =>
    t.run(async (c) => {
      await c.db.insert("programs", { userId, programId: "p1", ...program, status: "active", rev: 1, createdAt: NOW, updatedAt: NOW, tests: [] } as never);
    });

  it("queries/programs:list reads today in the zone of the caller", async () => {
    await make(USER_A);
    await make(USER_B);
    await t.run((c) => c.db.insert("users", { userId: USER_A, createdAt: NOW, timezone: "Pacific/Auckland" })); // 20 Nov there
    const a = (await t.query(api.queries.programs.list, { token: TOKEN })) as { now: { state: string } }[];
    const b = (await t.query(api.queries.programs.list, { token: TOKEN_B })) as { now: { state: string } }[];
    expect(a[0]!.now.state).toBe("running"); // A is on 20 Nov
    expect(b[0]!.now.state).toBe("before"); // B has no zone: UTC, still 19 Nov
    vi.stubEnv("APP_TIMEZONE", "Pacific/Auckland");
    const b2 = (await t.query(api.queries.programs.list, { token: TOKEN_B })) as { now: { state: string } }[];
    expect(b2[0]!.now.state).toBe("running"); // the deployment's zone, for a user with no zone
  });

  it("the input of a job carries the zone of its user", async () => {
    await t.run(async (c) => {
      await c.db.insert("users", { userId: USER_A, createdAt: NOW, timezone: "Pacific/Auckland" });
    });
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: { sessionId: "s1", kind: "activity", type: "Run", startedAt: NOW - 3_600_000, endedAt: NOW - 1_800_000, exercises: [], source: "app" } });
    await t.mutation(api.commands.sessions.save, { token: TOKEN_B, session: { sessionId: "s1", kind: "activity", type: "Run", startedAt: NOW - 3_600_000, endedAt: NOW - 1_800_000, exercises: [], source: "app" } });
    const a = (await t.query(internal.jobs.reviews.input, { userId: USER_A, sessionId: "s1" })) as { timeZone: string; picture: { today: string } };
    const b = (await t.query(internal.jobs.reviews.input, { userId: USER_B, sessionId: "s1" })) as { timeZone: string; picture: { today: string } };
    expect(a.timeZone).toBe("Pacific/Auckland");
    expect(b.timeZone).toBe("UTC");
    await settle(t);
  });
});
