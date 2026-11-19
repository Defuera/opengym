import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../functions/_generated/api";
import { DELETE_AFTER_MS, PROPOSAL_TTL_MS } from "../functions/lib/constants";
import { MOCK_PROGRAM } from "../functions/model/ai/providers/mock";
import type { PlanExercise, ProgramValue } from "../functions/model/schema";
import { TOKEN, setup, settle, stubOpenAi, type T } from "./helpers";

/** Program step 1: the shared proposal block (request, build, accept, decline), the program commands and queries, the session link. */
const NOW = Date.UTC(2026, 10, 19, 12); // Thursday 19 Nov 2026
const HOUR = 3_600_000;
const DAY = 24 * HOUR;
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

const ex = (name: string, kg: number): PlanExercise => ({ name, sets: [{ reps: 8, kg, max: false }, { reps: 8, kg, max: false }] });
const sessionsOf = (keys: string[]) => keys.map((key) => ({ key, title: `Session ${key}`, activity: "Gym", exercises: [ex("Squat", 40), ex("Row", 30)] }));
/** 19 Nov to 2 Dec: two weeks; a week is A, B, A. */
const value = (over: Partial<ProgramValue> = {}): ProgramValue => ({
  title: "Knee for skiing",
  purpose: "Be ready by December",
  startsOn: "2026-11-19",
  endsOn: "2026-12-02",
  week: ["A", "B", "A"],
  phases: [
    { title: "Base", weekFrom: 1, weekTo: 1, note: "", sessions: sessionsOf(["A", "B"]) },
    { title: "Build", weekFrom: 2, weekTo: 2, note: "heavier", sessions: sessionsOf(["A", "B"]).map((s) => ({ ...s, exercises: [ex("Squat", 50), ex("Row", 35)] })) },
  ],
  rules: ["No deep squats"],
  tests: ["Squat 10 reps", "One-leg hop"],
  ...over,
});
const built = (v: ProgramValue = value()) => JSON.stringify({ ...v, reason: "Matches your text" });
const answer = (v: ProgramValue = value()) => (job: string) => (job === "build_program" ? built(v) : "{}");

const req = (proposalId: string, extra: Record<string, unknown> = { text: "knee for skiing by 2 Dec" }) => t.mutation(api.commands.proposals.request, { token: TOKEN, proposalId, kind: "program", ...extra } as never);
const rebuild = (proposalId: string, previousProposalId: string, feedback = "more cycling") => req(proposalId, { feedback, previousProposalId });
const accept = (proposalId: string) => t.mutation(api.commands.proposals.accept, { token: TOKEN, proposalId });
const decline = (proposalId: string) => t.mutation(api.commands.proposals.decline, { token: TOKEN, proposalId });
const prop = (proposalId: string) => t.run((c) => c.db.query("proposals").withIndex("by_proposalId", (q) => q.eq("proposalId", proposalId)).unique());
const getP = (proposalId: string) => t.query(api.queries.proposals.get, { token: TOKEN, proposalId });
const programs = () => t.run((c) => c.db.query("programs").collect());
const list = () => t.query(api.queries.programs.list, { token: TOKEN });
/** A proposal that went through the build with the stubbed AI and is ready. */
async function ready(proposalId: string, v: ProgramValue = value(), extra?: Record<string, unknown>) {
  stubOpenAi(answer(v));
  await req(proposalId, extra);
  await settle(t);
  expect((await prop(proposalId))!.status).toBe("ready");
}
async function newProgram(proposalId = "p1", v: ProgramValue = value()) {
  await ready(proposalId, v);
  return (await accept(proposalId)).programId;
}
const session = (sessionId: string, link: Record<string, unknown> = {}, exercises = [ex("Squat", 60)], endedAt = NOW - HOUR) => ({
  sessionId, kind: "gym" as const, type: "Gym", startedAt: endedAt - HOUR, endedAt, exercises, source: "app" as const, ...link,
});
const save = (s: ReturnType<typeof session>) => t.mutation(api.commands.sessions.save, { token: TOKEN, session: s });

describe("commands/proposals:request", () => {
  it("is idempotent by proposalId", async () => {
    await req("p1");
    await req("p1", { text: "another text" });
    const rows = await t.run((c) => c.db.query("proposals").collect());
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ proposalId: "p1", status: "building", origin: "request", approval: "explicit", target: { kind: "program" }, ask: { text: "knee for skiing by 2 Dec" } });
    expect(rows[0]!.base).toBeUndefined();
    await settle(t);
  });

  it("validates the ids, the text and the feedback, and the token", async () => {
    await expect(req(" ")).rejects.toThrow(/proposalId must be 1\.\.100/);
    await expect(req("x".repeat(101))).rejects.toThrow(/proposalId must be 1\.\.100/);
    await expect(req("p1", {})).rejects.toThrow(/text must be 1\.\.8000/);
    await expect(req("p1", { text: "   " })).rejects.toThrow(/text must be 1\.\.8000/);
    await expect(req("p1", { text: "x".repeat(8001) })).rejects.toThrow(/text must be 1\.\.8000/);
    await expect(req("p1", { feedback: "more" })).rejects.toThrow(/go together/);
    await expect(req("p1", { previousProposalId: "a" })).rejects.toThrow(/go together/);
    await expect(req("p1", { feedback: " ", previousProposalId: "a" })).rejects.toThrow(/feedback must be 1\.\.1000/);
    await expect(req("p1", { feedback: "x".repeat(1001), previousProposalId: "a" })).rejects.toThrow(/feedback must be 1\.\.1000/);
    await expect(t.mutation(api.commands.proposals.request, { token: "bad", proposalId: "p1", kind: "program", text: "a" })).rejects.toThrow(/unauthorized/);
    expect(await t.run((c) => c.db.query("proposals").collect())).toHaveLength(0);
    await expect(req("p1", { text: "a", targetId: "nope" })).rejects.toThrow(/program not found/);
    expect(await t.run((c) => c.db.query("proposals").collect())).toHaveLength(0);
  });

  it("a rebuild copies target and ask text, keeps at most 5 feedback rounds, and declines the previous row", async () => {
    stubOpenAi(answer());
    await req("r0");
    await settle(t);
    for (let i = 1; i <= 6; i++) {
      await rebuild(`r${i}`, `r${i - 1}`, `f${i}`);
      await settle(t);
    }
    expect(await prop("r6")).toMatchObject({ origin: "feedback", status: "ready", ask: { text: "knee for skiing by 2 Dec", feedback: ["f2", "f3", "f4", "f5", "f6"], previousProposalId: "r5" } });
    for (let i = 0; i <= 5; i++) expect((await prop(`r${i}`))!.status).toBe("declined");
  });

  it("a rebuild needs a previous row that exists and is ready, and writes nothing otherwise", async () => {
    await expect(rebuild("b", "missing")).rejects.toThrow(/previous proposal not found/);
    await req("a"); // building
    await expect(rebuild("b", "a")).rejects.toThrow(/not ready/);
    expect(await prop("b")).toBeNull();
    expect((await prop("a"))!.status).toBe("building");
    await settle(t);
  });

  it("with targetId it is a change: base is the rev, the program must exist, a rebuild keeps the target", async () => {
    const programId = await newProgram();
    stubOpenAi(answer());
    await req("c1", { text: "make it lighter", targetId: programId });
    expect(await prop("c1")).toMatchObject({ target: { kind: "program", id: programId }, base: 1 });
    await settle(t);
    await rebuild("c2", "c1");
    expect(await prop("c2")).toMatchObject({ target: { kind: "program", id: programId }, base: 1, ask: { text: "make it lighter" } });
    await settle(t);
  });

  it("removes proposals older than 7 days", async () => {
    stubOpenAi(answer());
    await req("old");
    await settle(t);
    await req("old2");
    await settle(t);
    vi.setSystemTime(NOW + PROPOSAL_TTL_MS + DAY);
    await req("new");
    expect(await prop("old")).toBeNull();
    expect(await prop("old2")).toBeNull();
    expect(await prop("new")).not.toBeNull();
    await settle(t);
  });
});

describe("jobs/programs:build", () => {
  it("makes a ready proposal from the AI answer, with the reason, source ai and the input the contract names", async () => {
    await t.mutation(api.commands.goals.create, { token: TOKEN, goalId: "g1", title: "Ski", kind: "custom" });
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: session("old", {}, [ex("Squat", 60)], NOW - 3 * DAY) });
    const calls = stubOpenAi(answer());
    await req("p1", { text: "prepare my knee for skiing by 2 Dec" });
    await settle(t);
    expect(await getP("p1")).toEqual({ proposalId: "p1", target: { kind: "program" }, status: "ready", approval: "explicit", origin: "request", value: value(), reason: "Matches your text", source: "ai", error: null });
    const input = calls.find((c) => c.job === "build_program")!.input;
    expect(input).toMatchObject({ request: "prepare my knee for skiing by 2 Dec", today: "2026-11-19 (Thursday)", exercisesTheUserKnows: [{ name: "Squat", lastSets: "8x60, 8x60", bestKg: 60 }] });
    expect(input.goalsInOrderOfPriority).toHaveLength(1);
    expect(input.limits).toEqual([]);
    expect(input).not.toHaveProperty("feedbackFromThePerson");
    expect(input).not.toHaveProperty("currentProgram");
  });

  it("a rebuild sends the previous program and the feedback; a change sends the current program", async () => {
    const calls = stubOpenAi(answer());
    await req("a");
    await settle(t);
    await rebuild("b", "a", "more cycling");
    await settle(t);
    const second = calls.filter((c) => c.job === "build_program")[1]!.input;
    expect(second).toMatchObject({ feedbackFromThePerson: ["more cycling"], previousProgram: value() });
    expect(await accept("b")).toEqual({ programId: "b" });
    await req("d", { text: "lighter", targetId: "b" });
    await settle(t);
    const last = calls.filter((c) => c.job === "build_program").at(-1)!.input;
    expect(last.currentProgram).toEqual(value());
  });

  it("an invalid answer (a phase gap) is retried once with the reason", async () => {
    const bad = value({ phases: [value().phases[0]!] });
    let n = 0;
    stubOpenAi((job) => (job === "build_program" ? built(n++ === 0 ? bad : value()) : "{}"));
    await req("p1");
    await settle(t);
    expect(n).toBe(2);
    expect((await prop("p1"))!.status).toBe("ready");
  });

  it("an AI that fails twice makes the proposal failed with a short error, and no program", async () => {
    stubOpenAi((job) => (job === "build_program" ? "not json" : "{}"));
    await req("p1");
    await settle(t);
    const p = (await prop("p1"))!;
    expect(p.status).toBe("failed");
    expect(p.error!.length).toBeLessThanOrEqual(200);
    expect(p.error).toMatch(/could not write the program/);
    expect(p.value).toBeUndefined();
    expect(await programs()).toHaveLength(0);
  });

  it("with the AI off the proposal is failed (no rules fallback)", async () => {
    await req("p1");
    await settle(t);
    expect(await prop("p1")).toMatchObject({ status: "failed", error: expect.stringMatching(/not configured/) });
  });

  it("a declined proposal is not changed by a late job", async () => {
    stubOpenAi(answer());
    await req("p1");
    await decline("p1");
    await settle(t);
    expect((await prop("p1"))!.status).toBe("declined");
    expect((await prop("p1"))!.value).toBeUndefined();
  });

  it("the mock provider answers build_program with a valid program", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await req("p1");
    await settle(t);
    const p = (await prop("p1"))!;
    expect(p.status).toBe("ready");
    expect(p.value!.title).toBe(MOCK_PROGRAM.title);
  });
});

describe("commands/proposals:accept, decline and the open list", () => {
  it("accept inserts an active program: rev 1, sourceText, tests with fresh ids; the proposal is applied", async () => {
    await ready("p1");
    expect(await accept("p1")).toEqual({ programId: "p1" });
    const [p] = await programs();
    expect(p).toMatchObject({ programId: "p1", title: "Knee for skiing", status: "active", rev: 1, sourceText: "knee for skiing by 2 Dec", rules: ["No deep squats"] });
    expect(p!.tests.map((x) => x.text)).toEqual(["Squat 10 reps", "One-leg hop"]);
    expect(new Set(p!.tests.map((x) => x.testId)).size).toBe(2);
    expect(await prop("p1")).toMatchObject({ status: "applied", decidedAt: expect.any(Number) });
    await expect(accept("p1")).rejects.toThrow(/not ready/);
    await settle(t);
  });

  it("accept needs a ready proposal", async () => {
    await expect(accept("none")).rejects.toThrow(/not found/);
    stubOpenAi(answer());
    await req("p1");
    await expect(accept("p1")).rejects.toThrow(/not ready/);
    await settle(t);
  });

  it("accept checks the limits of this moment again and throws the reason", async () => {
    await ready("p1");
    await t.mutation(api.commands.limits.save, { token: TOKEN, limit: { limitId: "k1", part: "left_knee", title: "Left knee", status: "active", rules: [{ kind: "avoid", text: "No deep squats", exercises: ["Squat"] }] } });
    await expect(accept("p1")).rejects.toThrow(/"Squat" is marked avoid/);
    expect((await prop("p1"))!.status).toBe("ready");
    expect(await programs()).toHaveLength(0);
    await settle(t);
  });

  it("accept of a change replaces the value, keeps id, status and createdAt, keeps the done day of an unchanged test, rev + 1", async () => {
    const programId = await newProgram();
    await t.run(async (c) => {
      const row = (await c.db.query("programs").first())!;
      await c.db.patch(row._id, { status: "paused", tests: row.tests.map((x, i) => (i === 0 ? { ...x, doneOn: "2026-11-25" } : x)) });
    });
    const before = (await programs())[0]!;
    const createdAt = before.createdAt;
    vi.setSystemTime(NOW + DAY);
    await ready("c1", value({ title: "Knee, lighter", tests: ["Squat 10 reps", "Step down"] }), { text: "lighter", targetId: programId });
    expect(await accept("c1")).toEqual({ programId });
    const [p] = await programs();
    expect(p).toMatchObject({ programId, title: "Knee, lighter", status: "paused", rev: 2, createdAt, sourceText: "knee for skiing by 2 Dec" });
    expect(p!.tests).toEqual([{ testId: before.tests[0]!.testId, text: "Squat 10 reps", doneOn: "2026-11-25" }, { testId: expect.any(String), text: "Step down" }]);
    expect(p!.tests[1]!.testId).not.toBe(before.tests[1]!.testId);
    expect((await prop("c1"))!.status).toBe("applied");
    await settle(t);
  });

  it("accept of a change with an old base throws, and the reads report the proposal as stale", async () => {
    const programId = await newProgram();
    await ready("c1", value({ title: "Lighter" }), { text: "lighter", targetId: programId });
    await t.mutation(api.commands.programs.setStatus, { token: TOKEN, programId, status: "paused" }); // rev 2
    await expect(accept("c1")).rejects.toThrow("The program changed. Ask again.");
    expect((await getP("c1"))!.status).toBe("stale");
    expect((await t.query(api.queries.proposals.open, { token: TOKEN })).map((p) => p.proposalId)).toEqual([]);
    expect((await programs())[0]).toMatchObject({ title: "Knee for skiing", rev: 2 });
    await settle(t);
  });

  it("accept of a change to a deleted program throws and reads as stale", async () => {
    const programId = await newProgram();
    await ready("c1", value({ title: "Lighter" }), { text: "lighter", targetId: programId });
    await t.mutation(api.commands.programs.remove, { token: TOKEN, programId });
    await expect(accept("c1")).rejects.toThrow("The program changed. Ask again.");
    expect((await getP("c1"))!.status).toBe("stale");
    await settle(t);
  });

  it("decline turns a building or ready proposal into declined, and leaves others", async () => {
    stubOpenAi(answer());
    await req("b");
    expect(await decline("b")).toBeNull();
    expect((await prop("b"))!.status).toBe("declined");
    await ready("r");
    await decline("r");
    expect((await prop("r"))!.status).toBe("declined");
    await newProgram("p9");
    await decline("p9");
    expect((await prop("p9"))!.status).toBe("applied");
    expect(await decline("unknown")).toBeNull();
    await settle(t);
  });

  it("queries/proposals:get gives null for an unknown id", async () => {
    expect(await getP("x")).toBeNull();
  });

  it("queries/proposals:open lists building and ready explicit proposals, newest first, at most 5", async () => {
    stubOpenAi(answer());
    for (let i = 0; i < 7; i++) {
      vi.setSystemTime(NOW + i * 1000);
      await req(`o${i}`);
    }
    await settle(t);
    await decline("o6");
    await t.run(async (c) => {
      const row = (await c.db.query("proposals").withIndex("by_proposalId", (q) => q.eq("proposalId", "o5")).unique())!;
      await c.db.patch(row._id, { status: "building" });
    });
    const open = await t.query(api.queries.proposals.open, { token: TOKEN });
    expect(open.map((p) => p.proposalId)).toEqual(["o5", "o4", "o3", "o2", "o1"]);
    expect(open[0]).toMatchObject({ status: "building", approval: "explicit", value: expect.anything() });
    await accept("o4");
    expect((await t.query(api.queries.proposals.open, { token: TOKEN })).map((p) => p.proposalId)).toEqual(["o5", "o3", "o2", "o1", "o0"]);
    await settle(t);
  });
});

describe("programs: setStatus, remove, purge", () => {
  it("setStatus changes the status and bumps the rev; an unknown program throws", async () => {
    const programId = await newProgram();
    expect(await t.mutation(api.commands.programs.setStatus, { token: TOKEN, programId, status: "paused" })).toBeNull();
    expect((await programs())[0]).toMatchObject({ status: "paused", rev: 2 });
    await t.mutation(api.commands.programs.setStatus, { token: TOKEN, programId, status: "paused" });
    expect((await programs())[0]!.rev).toBe(2);
    await t.mutation(api.commands.programs.setStatus, { token: TOKEN, programId, status: "active" });
    expect((await programs())[0]).toMatchObject({ status: "active", rev: 3 });
    await expect(t.mutation(api.commands.programs.setStatus, { token: TOKEN, programId: "nope", status: "done" })).rejects.toThrow(/program not found/);
    await settle(t);
  });

  it("remove marks, hides the program from every read, and the purge erases it after 72 hours", async () => {
    const programId = await newProgram();
    expect(await t.mutation(api.commands.programs.remove, { token: TOKEN, programId })).toBeNull();
    expect((await programs())[0]!.deletedAt).toBeGreaterThanOrEqual(NOW);
    expect(await list()).toEqual([]);
    await expect(t.mutation(api.commands.programs.setStatus, { token: TOKEN, programId, status: "done" })).rejects.toThrow(/not found/);
    await t.mutation(internal.jobs.purge.run, {});
    expect(await programs()).toHaveLength(1);
    vi.setSystemTime(NOW + DELETE_AFTER_MS + 1000);
    await t.mutation(internal.jobs.purge.run, {});
    expect(await programs()).toHaveLength(0);
    await settle(t);
  });
});

describe("queries/programs:list and the session link", () => {
  it("gives the program with its now block: running, week 1, slots, next with the written exercises", async () => {
    const programId = await newProgram();
    const [p] = await list();
    expect(p).toMatchObject({ programId, title: "Knee for skiing", purpose: "Be ready by December", status: "active", startsOn: "2026-11-19", endsOn: "2026-12-02", week: ["A", "B", "A"], rules: ["No deep squats"], rev: 1 });
    expect(p!.tests).toHaveLength(2);
    expect(p!.phases).toHaveLength(2);
    expect(p!.now).toMatchObject({ state: "running", week: 1, weeks: 2, phaseIndex: 0 });
    expect(p!.now.slots).toEqual([{ slot: 1, key: "A", title: "Session A", done: false }, { slot: 2, key: "B", title: "Session B", done: false }, { slot: 3, key: "A", title: "Session A", done: false }]);
    expect(p!.now.next).toMatchObject({ slot: 1, key: "A", title: "Session A", activity: "Gym", exercises: [ex("Squat", 40), ex("Row", 30)] });
    await settle(t);
  });

  it("a saved session with the link marks the slot done and moves next; the link is stored and survives an old-build resave", async () => {
    const programId = await newProgram();
    const link = { programId, programWeek: 1, programSlot: 1, programKey: "A" };
    await save(session("s1", link));
    const stored = await t.run((c) => c.db.query("sessions").withIndex("by_sessionId", (q) => q.eq("sessionId", "s1")).unique());
    expect(stored).toMatchObject(link);
    const [p] = await list();
    expect(p!.now.slots.map((s) => s.done)).toEqual([true, false, false]);
    expect(p!.now.next).toMatchObject({ slot: 2, key: "B" });
    // an old app build resends the session without the link: the stored link stays
    await save(session("s1", {}, [ex("Squat", 61)]));
    expect((await t.run((c) => c.db.query("sessions").collect()))[0]).toMatchObject({ ...link });
    expect((await list())[0]!.now.slots[0]!.done).toBe(true);
    await settle(t);
  });

  it("a removed session no longer counts; every slot done means next is null", async () => {
    const programId = await newProgram();
    for (const [i, key] of ["A", "B", "A"].entries()) await save(session(`s${i}`, { programId, programWeek: 1, programSlot: i + 1, programKey: key }));
    expect((await list())[0]!.now.next).toBeNull();
    await t.mutation(api.commands.sessions.remove, { token: TOKEN, sessionId: "s1" });
    expect((await list())[0]!.now).toMatchObject({ slots: [{ done: true }, { done: false }, { done: true }], next: { slot: 2 } });
    await settle(t);
  });

  it("fills the kg of next: the last program session of the same key first, then the log, then the written kg", async () => {
    const programId = await newProgram();
    await save(session("log1", {}, [ex("Row", 44)], NOW - 5 * DAY)); // another log session with Row
    await save(session("s1", { programId, programWeek: 1, programSlot: 1, programKey: "A" }, [ex("squat", 62)], NOW - 2 * HOUR));
    vi.setSystemTime(NOW + 7 * DAY); // week 2: slot 1 (key A) is open again
    const [p] = await list();
    expect(p!.now).toMatchObject({ week: 2, phaseIndex: 1 });
    // phase 2 writes Squat 50 and Row 35: Squat from the program session (62), Row from the log (44)
    expect(p!.now.next!.exercises).toEqual([ex("Squat", 62), ex("Row", 44)]);
    await settle(t);
  });

  it("is before the start, ended after the end, and has no next for a paused program", async () => {
    const programId = await newProgram("p1", value({ startsOn: "2026-11-25", endsOn: "2026-12-08" })); // starts in 6 days
    expect((await list())[0]!.now).toMatchObject({ state: "before", week: 1, next: null });
    vi.setSystemTime(Date.UTC(2026, 11, 3, 12));
    expect((await list())[0]!.now).toMatchObject({ state: "running", week: 2, next: { slot: 1 } });
    await t.mutation(api.commands.programs.setStatus, { token: TOKEN, programId, status: "paused" });
    expect((await list())[0]!.now).toMatchObject({ state: "running", next: null });
    await t.mutation(api.commands.programs.setStatus, { token: TOKEN, programId, status: "active" });
    vi.setSystemTime(Date.UTC(2026, 11, 9, 12));
    expect((await list())[0]!.now).toMatchObject({ state: "ended", week: 2, next: null });
    await settle(t);
  });

  it("reads today in APP_TIMEZONE at the edge of midnight", async () => {
    await newProgram("p1", value({ startsOn: "2026-11-20", endsOn: "2026-12-03" }));
    vi.setSystemTime(Date.UTC(2026, 10, 19, 23, 30));
    expect((await list())[0]!.now.state).toBe("before");
    vi.stubEnv("APP_TIMEZONE", "Pacific/Auckland"); // already 20 Nov there
    expect((await list())[0]!.now).toMatchObject({ state: "running", week: 1 });
    await settle(t);
  });

  it("lists newest first and needs the token", async () => {
    await newProgram("p1");
    vi.setSystemTime(NOW + HOUR);
    await newProgram("p2");
    expect((await list()).map((p) => p.programId)).toEqual(["p2", "p1"]);
    await expect(t.query(api.queries.programs.list, { token: "bad" })).rejects.toThrow(/unauthorized/);
    await settle(t);
  });
});

describe("commands/start:request with previousPlan", () => {
  const plan = [{ name: "Squat", sets: [{ reps: 8, kg: 40, max: false }] }, { name: "Bike", measure: "time" as const, sets: [{ minutes: 20 }] }];
  const start = (requestId: string, extra: Record<string, unknown>) => t.mutation(api.commands.start.request, { token: TOKEN, requestId, ...extra } as never);
  const row = (requestId: string) => t.run((c) => c.db.query("startRequests").withIndex("by_requestId", (q) => q.eq("requestId", requestId)).unique());

  it("takes feedback with previousPlan and name instead of previousRequestId", async () => {
    await start("a", { name: "Session A", feedback: "  no squats  ", previousPlan: plan });
    expect(await row("a")).toMatchObject({ name: "Session A", feedback: ["no squats"], previousPlan: plan, status: "pending" });
    await settle(t);
  });

  it("the job rebuilds with the plan and the feedback; a failed AI means failed", async () => {
    const calls = stubOpenAi((job) => (job === "build_session" ? JSON.stringify({ kind: "gym", type: "Session A", plan: { rationale: "r", exercises: [{ name: "Lunge", sets: [{ reps: 10, kg: 0, max: false }] }] } }) : "{}"));
    await start("a", { name: "Session A", feedback: "no squats", previousPlan: plan });
    await settle(t);
    expect((await row("a"))!.status).toBe("ready");
    expect(calls.find((c) => c.job === "build_session")!.input).toMatchObject({ activity: "Session A", feedbackFromThePerson: ["no squats"], previousPlan: plan });
    vi.unstubAllGlobals();
    vi.stubEnv("AI_PROVIDER", "none");
    await start("b", { name: "Session A", feedback: "no squats", previousPlan: plan });
    await settle(t);
    expect((await row("b"))!.status).toBe("failed");
  });

  it("needs exactly one of previousRequestId and previousPlan, and a name with the plan", async () => {
    await expect(start("a", { name: "S", feedback: "x" })).rejects.toThrow(/go together/);
    await expect(start("a", { name: "S", previousPlan: plan })).rejects.toThrow(/go together/);
    await expect(start("a", { name: "S", feedback: "x", previousPlan: plan, previousRequestId: "p" })).rejects.toThrow(/not both/);
    await expect(start("a", { feedback: "x", previousPlan: plan })).rejects.toThrow(/name must be 1\.\.40/);
    await expect(start("a", { name: "x".repeat(41), feedback: "x", previousPlan: plan })).rejects.toThrow(/name must be 1\.\.40/);
    await expect(start("a", { name: "S", feedback: "x", previousPlan: [] })).rejects.toThrow(/previousPlan must have 1\.\.30/);
    expect(await row("a")).toBeNull();
  });
});
