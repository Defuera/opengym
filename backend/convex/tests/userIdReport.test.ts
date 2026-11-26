import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { internal } from "../functions/_generated/api";
import { NOW, PER_USER_TABLES, TOKEN, TOKEN_B, seedUser, setupTwo, USER_A } from "./multiUser";
import type { T } from "./helpers";

/** ADR-039: the report an operator reads before and after the rollout (jobs/migrations:userIdReport). */
let t: T;
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

describe("jobs/migrations:userIdReport and ensureOwner", () => {
  it("counts the rows of every per-user table, none without a user id, in small pages too", async () => {
    await seedUser(t, TOKEN, "A");
    await seedUser(t, TOKEN_B, "B");
    for (const batch of [undefined, 1]) {
      const r = await t.action(internal.jobs.migrations.userIdReport, batch === undefined ? {} : { batch });
      expect(Object.keys(r.tables).sort()).toEqual([...PER_USER_TABLES].sort());
      expect(r.withoutUserId).toBe(0);
      for (const table of PER_USER_TABLES) {
        const rows = await t.run((c) => c.db.query(table).collect());
        expect(r.tables[table]).toEqual({ total: rows.length, withoutUserId: 0 });
        expect(rows.length).toBeGreaterThan(1);
      }
    }
  });

  it("ensureOwner makes the owner user once; the report shows it", async () => {
    expect((await t.action(internal.jobs.migrations.userIdReport, {})).ownerUser).toBe(false);
    expect(await t.mutation(internal.jobs.migrations.ensureOwner, {})).toBe(true);
    expect(await t.mutation(internal.jobs.migrations.ensureOwner, {})).toBe(false);
    expect((await t.run((c) => c.db.query("users").collect())).map((u) => u.userId)).toEqual([USER_A]);
    expect((await t.action(internal.jobs.migrations.userIdReport, {})).ownerUser).toBe(true);
  });
});
