import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { internal } from "../functions/_generated/api";
import { NOW, PER_USER_TABLES, TOKEN, seedUser, USER_A } from "./multiUser";
import { setup, type T } from "./helpers";

/** ADR-039, deploy point 1: the migration that gives every old row (a row with no userId) to the owner. */
let t: T;
beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
  t = setup();
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

/** Makes the live database as it is before the migration: every row has lost its userId (the table `users` stays empty). */
async function makeOld(): Promise<number> {
  await seedUser(t, TOKEN, "A");
  let n = 0;
  await t.run(async (c) => {
    await c.db.query("users").collect().then((us) => Promise.all(us.map((u) => c.db.delete(u._id))));
    for (const table of PER_USER_TABLES) {
      for (const r of await c.db.query(table).collect()) {
        if (table === "aiUsage") continue; // aiUsage always had a userId (ADR-038)
        await c.db.patch(r._id, { userId: undefined } as never);
        n++;
      }
    }
  });
  return n;
}
const report = () => t.action(internal.jobs.migrations.userIdReport, {});
const assign = (batch?: number) => t.action(internal.jobs.migrations.assignOwner, batch === undefined ? {} : { batch });

describe("jobs/migrations:assignOwner and userIdReport", () => {
  it("the report counts the rows with no user id, per table", async () => {
    const n = await makeOld();
    const r = await report();
    expect(n).toBeGreaterThan(25);
    expect(r.ownerUser).toBe(false);
    expect(r.withoutUserId).toBe(n);
    expect(Object.keys(r.tables).sort()).toEqual([...PER_USER_TABLES].sort());
    expect(r.tables.sessions!.total).toBeGreaterThan(1);
    expect(r.tables.sessions!.withoutUserId).toBe(r.tables.sessions!.total);
    expect(r.tables.aiUsage!.withoutUserId).toBe(0); // never had none
    expect(r.tables.aiUsage!.total).toBeGreaterThan(0);
  });

  it("gives every row to the owner, makes the owner user, and returns the counts", async () => {
    const n = await makeOld();
    const out = await assign();
    expect(out.users).toBe(true);
    expect(Object.values(out.tables).reduce((s, x) => s + x.assigned, 0)).toBe(n);
    for (const table of PER_USER_TABLES) {
      const rows = await t.run((c) => c.db.query(table).collect());
      expect(rows.length).toBe(out.tables[table]!.read);
      for (const r of rows) expect(r.userId).toBe(USER_A);
    }
    const users = await t.run((c) => c.db.query("users").collect());
    expect(users.map((u) => u.userId)).toEqual([USER_A]);
    const r = await report();
    expect(r.withoutUserId).toBe(0);
    expect(r.ownerUser).toBe(true);
  });

  it("a second run changes nothing", async () => {
    await makeOld();
    await assign();
    const before = await t.run(async (c) => Object.fromEntries(await Promise.all(PER_USER_TABLES.map(async (x) => [x, await c.db.query(x).collect()] as const))));
    const out = await assign();
    expect(out.users).toBe(false);
    expect(Object.values(out.tables).every((x) => x.assigned === 0)).toBe(true);
    const after = await t.run(async (c) => Object.fromEntries(await Promise.all(PER_USER_TABLES.map(async (x) => [x, await c.db.query(x).collect()] as const))));
    expect(after).toEqual(before);
    expect(await t.run((c) => c.db.query("users").collect())).toHaveLength(1);
  });

  it("works in small pages and keeps every other field", async () => {
    await makeOld();
    const before = await t.run((c) => c.db.query("sessions").collect());
    const out = await assign(1);
    expect(out.tables.sessions!.assigned).toBe(before.length);
    const after = await t.run((c) => c.db.query("sessions").collect());
    expect(after.map(({ userId: _u, ...rest }) => rest)).toEqual(before.map(({ userId: _u, ...rest }) => rest));
  });

  it("a row that has a user id is never changed", async () => {
    await makeOld();
    const id = (await t.run((c) => c.db.query("goals").first()))!._id;
    await t.run((c) => c.db.patch(id, { userId: "someone" } as never));
    const out = await assign();
    expect(out.tables.goals!.assigned).toBe(0);
    expect((await t.run((c) => c.db.get(id)))!.userId).toBe("someone");
  });

  it("resumes after a stop: only the rows still without a user id are written", async () => {
    await makeOld();
    const rows = await t.run((c) => c.db.query("entries").collect());
    await t.run((c) => c.db.patch(rows[0]!._id, { userId: USER_A } as never));
    const out = await assign();
    expect(out.tables.entries!.assigned).toBe(rows.length - 1);
  });
});
