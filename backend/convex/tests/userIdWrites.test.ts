import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { NOW, PER_USER_TABLES, TOKEN, seedUser, USER_A } from "./multiUser";
import { setup, type T } from "./helpers";

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

describe("every write sets the user id (ADR-039, deploy point 1)", () => {
  it("every row of every per-user table made by the real functions has userId owner", async () => {
    await seedUser(t, TOKEN, "A");
    const missing: string[] = [];
    const empty: string[] = [];
    for (const table of PER_USER_TABLES) {
      const rows = await t.run((c) => c.db.query(table).collect());
      if (rows.length === 0) empty.push(table);
      for (const r of rows) if (r.userId !== USER_A) missing.push(`${table}:${String(r._id)}`);
    }
    expect(missing).toEqual([]);
    expect(empty).toEqual([]);
  });
});
