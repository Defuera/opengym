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

const gym = (startedAt: number) => ({
  kind: "gym",
  type: "Push",
  startedAt,
  endedAt: startedAt + 3_600_000,
  exercises: [{ name: "Bench press", sets: [{ reps: 5, kg: 60, max: false }] }],
});
const body = () => ({
  sessions: [gym(1_000_000), { ...gym(9_000_000), id: "keep-me" }, { kind: "activity", type: "Run", startedAt: 20_000_000, endedAt: 21_800_000, minutes: 30, distanceKm: 5 }] as unknown[],
  goals: [{ title: "Bench 80", kind: "strength", exercise: "Bench press", targetKg: 80 }] as unknown[],
  context: [{ text: "Left ankle is tight", topic: "ankle" }] as unknown[],
  note: "from spreadsheet",
});
const counts = async () => ({
  sessions: (await t.run((c) => c.db.query("sessions").collect())).length,
  goals: (await t.run((c) => c.db.query("goals").collect())).length,
  context: (await t.run((c) => c.db.query("context").collect())).length,
  jobs: (await t.run((c) => c.db.query("imports").collect())).length,
});

describe("imports:loadStructured", () => {
  it("loads ready items as one done job without per-session reviews", async () => {
    const job = await t.mutation(api.commands.imports.loadStructured, { token: TOKEN, ...body() });
    expect(job).toMatchObject({ status: "done", total: 5, processed: 5, counts: { sessions: 3, goals: 1, context: 1 }, notes: ["from spreadsheet"] });

    const sessions = await t.query(api.queries.sessions.since, { token: TOKEN, since: 0 });
    expect(sessions).toHaveLength(3);
    for (const s of sessions) expect(s).toMatchObject({ source: "import", importId: job.importId });
    expect(sessions.map((s) => s.sessionId)).toContain("keep-me");
    expect((await t.query(api.queries.goals.list, { token: TOKEN }))[0]).toMatchObject({ status: "active", source: "import", importId: job.importId });
    expect((await t.query(api.queries.context.list, { token: TOKEN }))[0]).toMatchObject({ active: true, source: "import", importId: job.importId });

    await settle(t);
    expect(await t.run((c) => c.db.query("reviews").collect())).toHaveLength(0);
    expect((await t.query(api.queries.imports.list, { token: TOKEN }))).toHaveLength(1);
    expect((await t.query(api.queries.imports.get, { token: TOKEN, importId: job.importId }))?.status).toBe("done");
  });

  it("names the bad item and writes nothing", async () => {
    const b = body();
    b.sessions[2] = { ...gym(5_000), endedAt: 1_000 };
    await expect(t.mutation(api.commands.imports.loadStructured, { token: TOKEN, ...b })).rejects.toThrow(/sessions\[2\].*endedAt must not be before startedAt/);
    await expect(t.mutation(api.commands.imports.loadStructured, { token: TOKEN, ...body(), goals: [{ title: "", kind: "strength" }] })).rejects.toThrow(/goals\[0\]/);
    await expect(t.mutation(api.commands.imports.loadStructured, { token: TOKEN, ...body(), context: [{ text: "x" }] })).rejects.toThrow(/context\[0\]/);
    await expect(t.mutation(api.commands.imports.loadStructured, { token: TOKEN, sessions: Array.from({ length: 2001 }, () => gym(1)) })).rejects.toThrow(/sessions/);
    expect(await counts()).toEqual({ sessions: 0, goals: 0, context: 0, jobs: 0 });
  });

  it("remove deletes sessions, goal, context and the job", async () => {
    const { importId } = await t.mutation(api.commands.imports.loadStructured, { token: TOKEN, ...body() });
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: { sessionId: "mine", kind: "activity", type: "Run", startedAt: 1, endedAt: 2, exercises: [], source: "app" } });
    expect(await t.mutation(api.commands.imports.remove, { token: TOKEN, importId })).toBe(true);
    expect(await counts()).toEqual({ sessions: 1, goals: 0, context: 0, jobs: 0 });
    expect(await t.mutation(api.commands.imports.remove, { token: TOKEN, importId })).toBe(false);
    await settle(t);
  });

  it("a resend with the same importId writes nothing twice", async () => {
    const a = await t.mutation(api.commands.imports.loadStructured, { token: TOKEN, importId: "imp-1", ...body() });
    const b = await t.mutation(api.commands.imports.loadStructured, { token: TOKEN, importId: "imp-1", ...body() });
    expect(b.importId).toBe(a.importId);
    expect(await counts()).toEqual({ sessions: 3, goals: 1, context: 1, jobs: 1 });
    await settle(t);
  });

  it("a big import runs in batches: running, then done; remove clears it in steps", async () => {
    const sessions = Array.from({ length: 1200 }, (_, i) => gym(1_000_000 + i * 10_000_000));
    const job = await t.mutation(api.commands.imports.loadStructured, { token: TOKEN, sessions, ...{ goals: body().goals } });
    expect(job).toMatchObject({ status: "running", total: 1201, processed: 0 });
    expect(await counts()).toMatchObject({ sessions: 0 }); // nothing written until the batches run
    await settle(t);
    expect((await t.query(api.queries.imports.get, { token: TOKEN, importId: job.importId }))).toMatchObject({ status: "done", processed: 1201 });
    expect(await counts()).toEqual({ sessions: 1200, goals: 1, context: 0, jobs: 1 });
    expect(await t.run((c) => c.db.query("rebuilds").first())).toMatchObject({ runs: 1 }); // one rebuild for the whole import

    await t.mutation(api.commands.imports.remove, { token: TOKEN, importId: job.importId });
    await settle(t);
    expect(await counts()).toEqual({ sessions: 0, goals: 0, context: 0, jobs: 0 });
  });
});
