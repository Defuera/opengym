import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "../functions/_generated/api";
import { START_REQUEST_TTL_MS } from "../functions/lib/constants";
import { buildSessionJob } from "../functions/model/ai/jobs/buildSession";
import { coachPicture } from "../functions/model/ai/jobs/coachPicture";
import { TOKEN, setup, settle, stubOpenAi, type T } from "./helpers";

let t: T;
const NOW = Date.UTC(2026, 10, 17, 12);
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

const first = (requestId: string, name = "Home", text?: string) => t.mutation(api.commands.start.request, { token: TOKEN, requestId, name, ...(text ? { text } : {}) });
const again = (requestId: string, feedback?: string, previousRequestId?: string, extra: object = {}) =>
  t.mutation(api.commands.start.request, { token: TOKEN, requestId, ...(feedback !== undefined ? { feedback } : {}), ...(previousRequestId !== undefined ? { previousRequestId } : {}), ...extra });
const row = (requestId: string) => t.run((c) => c.db.query("startRequests").withIndex("by_requestId", (q) => q.eq("requestId", requestId)).unique());
const get = (requestId: string) => t.query(api.queries.start.request, { token: TOKEN, requestId });
const plan = (n: string) => ({ rationale: "r", exercises: [{ name: n, sets: [{ reps: 10, kg: 0, max: false }, { reps: 8, kg: 5, max: false }], note: "slow" }] });
const answer = (n: string) => (job: string) => (job === "build_session" ? JSON.stringify({ kind: "gym", type: "Home", plan: plan(n) }) : "{}");
const builds = (calls: { job: string; input: any }[]) => calls.filter((c) => c.job === "build_session"); // eslint-disable-line @typescript-eslint/no-explicit-any

describe("commands/start:request with feedback", () => {
  it("needs both feedback and previousRequestId, or neither", async () => {
    await first("a");
    await expect(again("b", "no bottles")).rejects.toThrow(/go together/);
    await expect(again("b", undefined, "a")).rejects.toThrow(/go together/);
    await settle(t);
  });

  it("feedback is 1..1000 after trim; previousRequestId 1..100", async () => {
    await first("a");
    await expect(again("b", "   ", "a")).rejects.toThrow(/feedback must be 1\.\.1000/);
    await expect(again("b", "x".repeat(1001), "a")).rejects.toThrow(/feedback must be 1\.\.1000/);
    await expect(again("b", "ok", " ")).rejects.toThrow(/previousRequestId/);
    await expect(again("b", "ok", "p".repeat(101))).rejects.toThrow(/previousRequestId/);
    await again("c", `  ${"x".repeat(1000)} `, "a");
    expect((await row("c"))!.feedback).toEqual(["x".repeat(1000)]);
    await settle(t);
  });

  it("rejects clearly when the previous row is gone, and writes nothing", async () => {
    await expect(again("b", "no bottles", "missing")).rejects.toThrow(/previous request not found/);
    expect(await row("b")).toBeNull();
    await first("a");
    vi.setSystemTime(NOW + START_REQUEST_TTL_MS + 1);
    await expect(again("b", "no bottles", "a")).rejects.toThrow(/previous request not found/);
    await settle(t);
  });

  it("copies name and text from the previous row (ignoring given ones), stores feedback and a compact plan", async () => {
    stubOpenAi(answer("Squat"));
    await first("a", "Home", "quick one");
    await settle(t);
    await again("b", " no water bottles, I have dumbbells ", "a", { name: "Other", text: "ignored" });
    expect(await row("b")).toMatchObject({
      name: "Home",
      text: "quick one",
      status: "pending",
      feedback: ["no water bottles, I have dumbbells"],
      previousPlan: [{ name: "Squat", sets: [{ reps: 10, kg: 0, max: false }, { reps: 8, kg: 5, max: false }] }],
    });
    expect((await row("b"))!.previousPlan![0]).not.toHaveProperty("note");
    await settle(t);
  });

  it("a resend of the same requestId changes nothing", async () => {
    stubOpenAi(answer("Squat"));
    await first("a", "Home");
    await settle(t);
    await again("b", "one", "a");
    await again("b", "two", "a");
    expect((await row("b"))!.feedback).toEqual(["one"]);
    await settle(t);
  });

  it("keeps the chain over rounds: at most 5, oldest dropped", async () => {
    stubOpenAi(answer("Squat"));
    await first("r0", "Home");
    await settle(t);
    for (let i = 1; i <= 6; i++) {
      await again(`r${i}`, `f${i}`, `r${i - 1}`);
      await settle(t);
    }
    expect((await row("r2"))!.feedback).toEqual(["f1", "f2"]);
    expect((await row("r6"))!.feedback).toEqual(["f2", "f3", "f4", "f5", "f6"]);
  });

  it("a request without the new args is unchanged: no feedback fields, no feedback in the job input", async () => {
    const calls = stubOpenAi(answer("Squat"));
    await first("a", "Home", "quick");
    await settle(t);
    const r = (await row("a"))!;
    expect(r.feedback).toBeUndefined();
    expect(r.previousPlan).toBeUndefined();
    expect(builds(calls)[0]!.input).not.toHaveProperty("feedbackFromThePerson");
    expect(builds(calls)[0]!.input).not.toHaveProperty("previousPlan");
  });
});

describe("build_session with feedback", () => {
  it("sends previousPlan and feedbackFromThePerson in INPUT_JSON, and the new proposal is ready", async () => {
    stubOpenAi(answer("Squat"));
    await first("a", "Home", "quick");
    await settle(t);
    const calls2 = stubOpenAi(answer("Goblet squat"));
    await again("b", "no water bottles, I have dumbbells", "a");
    await settle(t);
    const input = builds(calls2)[0]!.input;
    expect(input).toMatchObject({ activity: "Home", noteForToday: "quick", feedbackFromThePerson: ["no water bottles, I have dumbbells"], previousPlan: [{ name: "Squat" }] });
    expect(await get("b")).toMatchObject({ status: "ready", proposal: { type: "Home", plan: { source: "ai", exercises: [{ name: "Goblet squat" }] } } });
  });

  it("the prompt has one short sentence for the two new fields", () => {
    const picture = coachPicture([], [], [], [], [], 0);
    const base = { name: "Home", note: "", picture, limits: [] };
    const plain = buildSessionJob.build(base);
    const withFb = buildSessionJob.build({ ...base, previousPlan: [{ name: "Squat", sets: [] }], feedbackFromThePerson: ["no bottles"] });
    expect(withFb.system).toBe(plain.system);
    expect(withFb.system.match(/previousPlan/g)).toHaveLength(1);
    expect(withFb.messages[0]!.content).toContain('"feedbackFromThePerson":["no bottles"]');
    expect(plain.messages[0]!.content).not.toContain("feedbackFromThePerson");
  });

  it("when the AI fails the request is failed, with no rules plan; a plain request still gets the rules plan", async () => {
    stubOpenAi(answer("Squat"));
    await first("a", "Home");
    await settle(t);
    vi.stubEnv("AI_PROVIDER", "none");
    await again("b", "no bottles", "a");
    await settle(t);
    expect(await get("b")).toEqual({ requestId: "b", status: "failed" });
    await first("c", "Home");
    await settle(t);
    expect(await get("c")).toMatchObject({ status: "ready", proposal: { plan: { source: "rules" } } });
  });

  it("when the AI answers with nonsense twice the request is failed too", async () => {
    stubOpenAi(answer("Squat"));
    await first("a", "Home");
    await settle(t);
    stubOpenAi(() => "not json");
    await again("b", "no bottles", "a");
    await settle(t);
    expect(await get("b")).toMatchObject({ status: "failed" });
  });
});
