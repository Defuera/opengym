import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "../functions/_generated/api";
import { TOKEN, pushSession, setup, settle, type T } from "./helpers";

let t: T;
beforeEach(() => {
  vi.useFakeTimers();
  t = setup();
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

describe("auth", () => {
  it("rejects a wrong or empty token on a command and on a query", async () => {
    await expect(t.mutation(api.commands.sessions.save, { token: "nope", session: pushSession("a", 1_000_000) })).rejects.toThrow(/unauthorized/);
    await expect(t.mutation(api.commands.goals.create, { token: "", goalId: "g", title: "x", kind: "custom" })).rejects.toThrow(/unauthorized/);
    await expect(t.query(api.queries.sessions.recent, { token: "nope" })).rejects.toThrow(/unauthorized/);
    await expect(t.query(api.queries.plans.next, { token: "nope", type: "Push" })).rejects.toThrow(/unauthorized/);
    await expect(t.query(api.queries.dashboard.get, { token: "nope", days: 7 })).rejects.toThrow(/unauthorized/);
    expect(await t.query(api.queries.sessions.recent, { token: TOKEN })).toEqual([]);
  });

  it("rejects every call when APP_TOKEN is not set", async () => {
    vi.stubEnv("APP_TOKEN", "");
    await expect(t.query(api.queries.sessions.recent, { token: "" })).rejects.toThrow(/unauthorized/);
  });
});

describe("sessions", () => {
  it("rejects bad sessions", async () => {
    const good = pushSession("a", 1_000_000);
    const bad = [
      { ...good, kind: "weights" },
      { ...good, exercises: [{ name: "", sets: [] }] },
      { ...good, exercises: [{ name: "Bench press", sets: [{ reps: 101, kg: 10, max: false }] }] },
      { ...good, exercises: [{ name: "Bench press", sets: [{ reps: 5, kg: 501, max: false }] }] },
      { ...good, exercises: [{ name: "Bench press", sets: [{ reps: 5.5, kg: 50, max: false }] }] },
      { ...good, kind: "activity" },
      { ...good, endedAt: good.startedAt - 1 },
      { ...good, source: "ai" },
      { ...good, type: "x".repeat(41) },
      { ...good, sessionId: "" },
    ];
    for (const b of bad) await expect(t.mutation(api.commands.sessions.save, { token: TOKEN, session: b as never })).rejects.toThrow();
    expect(await t.query(api.queries.sessions.recent, { token: TOKEN })).toEqual([]);
  });

  it("names the problem in a ConvexError the client can read", async () => {
    const s = { ...pushSession("a", 5_000_000), startedAt: 4_500_000, endedAt: 4_000_000 };
    await expect(t.mutation(api.commands.sessions.save, { token: TOKEN, session: s })).rejects.toThrow(/endedAt must not be before startedAt/);
  });

  it("keeps the failed flag on a set", async () => {
    const s = pushSession("f", 2_000_000);
    s.exercises[0]!.sets[1] = { reps: 6, kg: 60, max: false, failed: true } as never;
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: s });
    const [stored] = await t.query(api.queries.sessions.recent, { token: TOKEN });
    expect(stored!.exercises[0]!.sets[1]).toMatchObject({ failed: true });
  });

  it("is an idempotent upsert; since honours endedAt and sorts oldest first", async () => {
    const s = pushSession("s1", 2_000_000);
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: s });
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: s });
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: pushSession("s2", 3_000_000) });
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: { ...s, note: "changed" } });
    const all = await t.query(api.queries.sessions.since, { token: TOKEN, since: 0 });
    expect(all.map((x) => x.sessionId)).toEqual(["s1", "s2"]);
    expect(all[0]!.note).toBe("changed");
    expect(await t.query(api.queries.sessions.since, { token: TOKEN, since: 2_000_000 })).toHaveLength(1);
    expect((await t.query(api.queries.sessions.recent, { token: TOKEN })).map((x) => x.sessionId)).toEqual(["s2", "s1"]);
    expect(await t.mutation(api.commands.sessions.remove, { token: TOKEN, sessionId: "s1" })).toBe(true);
    expect(await t.mutation(api.commands.sessions.remove, { token: TOKEN, sessionId: "s1" })).toBe(false);
    await settle(t);
  });

  it("a session write produces a review in the background, not for imports", async () => {
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: pushSession("p1", 5_000_000) });
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: { ...pushSession("p2", 6_000_000), source: "import" as const, importId: "imp" } });
    await settle(t);
    const r1 = await t.query(api.queries.reviews.get, { token: TOKEN, sessionId: "p1" });
    expect(r1).toMatchObject({ stored: true, review: { sessionId: "p1", source: "rules" } });
    expect(await t.run((ctx) => ctx.db.query("reviews").collect())).toHaveLength(1);
  });

  it("removing a session hides its review; the review row goes with the purge (see softDelete.test.ts)", async () => {
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: pushSession("p1", 5_000_000) });
    await settle(t);
    await t.mutation(api.commands.sessions.remove, { token: TOKEN, sessionId: "p1" });
    await settle(t);
    expect(await t.run((ctx) => ctx.db.query("reviews").collect())).toHaveLength(1);
    expect(await t.query(api.queries.reviews.get, { token: TOKEN, sessionId: "p1" })).toEqual({ review: null, stored: false });
  });
});
