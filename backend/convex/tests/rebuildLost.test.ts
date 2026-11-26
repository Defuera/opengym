import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "../functions/_generated/api";
import { REBUILD_DEBOUNCE_MS, REBUILD_MAX_WAIT_MS } from "../functions/lib/constants";
import { TOKEN, setup, settle, type T } from "./helpers";

/** A runner that was lost (for example a job queued under the arguments of an older deploy) must not block the rebuilds for ever (ADR-039 rollout). */
const NOW = Date.UTC(2026, 10, 26, 12);
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
const state = () => t.run((c) => c.db.query("rebuilds").first());
const add = (goalId: string) => t.mutation(api.commands.goals.create, { token: TOKEN, goalId, title: "Bench 80", kind: "custom" });

describe("markFactsChanged and a lost runner", () => {
  it("a flag older than the debounce and the max wait is taken as lost: a new runner is scheduled and runs", async () => {
    await t.run((c) => c.db.insert("rebuilds", { userId: "owner", dirtyAt: NOW - REBUILD_DEBOUNCE_MS - REBUILD_MAX_WAIT_MS - 1, dirtySince: NOW - 99_000, runnerScheduled: true, runs: 3 }));
    await add("g1");
    expect(await state()).toMatchObject({ runnerScheduled: true, dirtyAt: NOW, dirtySince: NOW });
    await settle(t);
    expect(await state()).toMatchObject({ runnerScheduled: false, runs: 4 });
  });

  it("a fresh flag stays as it was: the runner that waits is not doubled", async () => {
    await t.run((c) => c.db.insert("rebuilds", { userId: "owner", dirtyAt: NOW - 1000, dirtySince: NOW - 2000, runnerScheduled: true, runs: 3 }));
    await add("g1");
    expect(await state()).toMatchObject({ runnerScheduled: true, dirtyAt: NOW, dirtySince: NOW - 2000 });
  });
});
