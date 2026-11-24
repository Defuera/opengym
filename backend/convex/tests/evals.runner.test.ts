// @vitest-environment node
import { mkdtempSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import type { CheckResult } from "../evals/assertions";
import { parseArgs } from "../evals/runner/args";
import { CASES, selectCases } from "../evals/cases";
import { aggregate, markdown } from "../evals/reporting/summary";
import { writeReports } from "../evals/reporting/write";
import { Budget } from "../evals/runner/budget";
import { setupProvider } from "../evals/runner/provider";
import { runAll, runOne } from "../evals/runner/run";

const ENV = { AI_PROVIDER: "openai", OPENAI_API_KEY: "test-key", OPENAI_MODEL: "base-model" };
const opts = { samples: 1, concurrency: 1, maxCalls: 50, timeoutMs: 5_000 };
const exs = (...names: string[]) => names.map((name) => ({ name, sets: [{ reps: 10, kg: 8, max: false }, { reps: 10, kg: 8, max: false }] }));
const plan = (...names: string[]) => JSON.stringify({ kind: "gym", type: "Home", place: "Home", plan: { rationale: "r", exercises: exs(...names) } });

/** A stubbed OpenAI endpoint: `reply` gets the job and the parsed body; the stub records bodies and gives usage. */
function stub(reply: (job: string, body: any) => string) { // eslint-disable-line @typescript-eslint/no-explicit-any
  const bodies: any[] = []; // eslint-disable-line @typescript-eslint/no-explicit-any
  const f = (async (_url: string, init: RequestInit) => {
    const body = JSON.parse(init.body as string);
    bodies.push(body);
    const job = (body.messages[0].content as string).match(/^JOB: (\w+)/m)?.[1] ?? "";
    return new Response(JSON.stringify({ choices: [{ message: { content: reply(job, body) } }], usage: { prompt_tokens: 100, completion_tokens: 20 } }), { status: 200 });
  }) as unknown as typeof fetch;
  return { f, bodies };
}
const one = (id: string) => selectCases({ caseId: id })[0]!;
const run = (id: string, reply: (job: string, body: any) => string) => { // eslint-disable-line @typescript-eslint/no-explicit-any
  const s = stub(reply);
  return runOne(one(id), 1, setupProvider(ENV, s.f), new Budget(50), opts).then((r) => ({ r, ...s }));
};
const gate = (r: { gates: CheckResult[] }, name: string) => r.gates.find((g) => g.name === name);

describe("eval runner against a stubbed provider", () => {
  it("a good plan passes every gate and the task; time and tokens are captured", async () => {
    const { r, bodies } = await run("bs-home-dumbbells-only", () => plan("Goblet squat", "Dumbbell row", "Push-up", "Glute bridge"));
    expect(r.status).toBe("done");
    expect(r.gates.filter((g) => !g.pass)).toEqual([]);
    expect(r.success).toBe(true);
    expect(r.calls).toBe(1);
    expect([r.promptTokens, r.completionTokens]).toEqual([100, 20]);
    expect(r.raw).toHaveLength(1);
    expect(bodies[0].model).toBe("base-model");
    expect(bodies[0].messages[1].content).toContain("placesTheCoachKnows"); // the real build_session prompt with the persona's places
    expect(JSON.stringify(bodies[0])).toContain("two 8 kg dumbbells".replace("two", "Two"));
  });

  it("a planted plan with bottles fails the equipment gate and the bottle gate", async () => {
    const { r } = await run("bs-home-dumbbells-only", () => plan("Bottle squat", "Bottle row", "Push-up", "Plank"));
    expect(r.gatesPass).toBe(false);
    expect(gate(r, "equipment")!.pass).toBe(false);
    expect(gate(r, "equipment")!.reason).toContain("bottle");
    expect(r.success).toBe(false);
  });

  it("a rebuild that keeps the bottles fails; one with dumbbells passes", async () => {
    const bad = await run("bs-rebuild-no-bottles", () => plan("Bottle squat", "Dumbbell row", "Push-up"));
    expect(gate(bad.r, "notContains planText")!.pass).toBe(false);
    const good = await run("bs-rebuild-no-bottles", () => plan("Goblet squat", "Dumbbell row", "Push-up"));
    expect(good.r.success).toBe(true);
    // the feedback and the plan the person saw reach the prompt, as on the server
    const user = good.bodies[0].messages[1].content as string;
    expect(user).toContain("feedbackFromThePerson");
    expect(user).toContain("Bottle squat");
    expect(user).toContain("I have no water bottles");
  });

  it("a planted plan with an avoided movement fails its gate (plural name passes the exact-name rule)", async () => {
    const jonasPlan = (...n: string[]) => JSON.stringify({ kind: "gym", type: "Gym", place: "Gym", plan: { rationale: "r", exercises: exs(...n) } });
    const plural = await run("bs-knee-legs-day", () => jonasPlan("Leg extensions", "Leg curl", "Hip thrust", "Calf raise"));
    expect(plural.r.status).toBe("done");
    expect(gate(plural.r, "noAvoided")!.pass).toBe(false);
    expect(plural.r.gatesPass).toBe(false);
    // the exact name is refused by the job's own check twice: retry, then the plain fallback
    const exact = await run("bs-knee-legs-day", () => jonasPlan("Leg extension", "Leg curl", "Hip thrust"));
    expect(exact.r.retried).toBe(true);
    expect(exact.r.fallback).toBe(true);
    expect(gate(exact.r, "model_answered")!.pass).toBe(false);
    expect(exact.r.calls).toBe(2);
    const good = await run("bs-knee-legs-day", () => jonasPlan("Romanian deadlift", "Leg curl", "Hip thrust", "Calf raise"));
    expect(good.r.gatesPass).toBe(true);
    expect(good.r.success).toBe(true);
  });

  it("the server's own checks run on the answer: the name is forced, the plan is cut to the minutes", async () => {
    const { r } = await run("bs-name-kept", () => JSON.stringify({ kind: "gym", type: "Something else", plan: { rationale: "r", exercises: exs("Goblet squat", "Dumbbell row", "Push-up") } }));
    expect(gate(r, "equals type")!.pass).toBe(true); // forced by the server step
    expect(r.warn.some((w) => !w.pass)).toBe(true); // the raw name was wrong: warning only
    const eight = Array.from({ length: 8 }, (_, i) => `Move ${i}`);
    const asked = (minutes?: number) => JSON.stringify({ kind: "gym", type: "Home", place: "Home", ...(minutes ? { minutes } : {}), plan: { rationale: "r", exercises: exs(...eight) } });
    const cut = await run("bs-short-15", () => asked(15)); // the server fits the plan to the minutes the model gave
    expect(gate(cut.r, "minutes")!.pass).toBe(true);
    const uncut = await run("bs-short-15", () => asked()); // no minutes: nothing is cut, 16 sets are about 32 minutes
    expect(gate(uncut.r, "minutes")!.pass).toBe(false);
  });

  it("chat: scripted turns, the coach's own earlier answer is in the next history", async () => {
    let n = 0;
    const answers = ["You should rest and see a doctor.", "Do 3 sets of leg curls."];
    const say = (message: string) => JSON.stringify({ message, actions: [] });
    const { r, bodies } = await run("ch-declined-advice", () => say(answers[n++]!));
    expect(bodies).toHaveLength(2);
    const second = bodies[1].messages as { role: string; content: string }[];
    expect(second.map((m) => m.role)).toEqual(["system", "user", "assistant", "user"]);
    expect(second[2]!.content).toBe(answers[0]);
    expect(r.success).toBe(true);
    let m = 0;
    const repeat = await run("ch-declined-advice", () => say(["Rest.", "Please rest and do 3 sets."][m++]!));
    expect(repeat.r.success).toBe(false);
    expect(repeat.r.expect[0]!.pass).toBe(false);
  });

  it("parse_log and learn_place run through the real job code", async () => {
    const p = await run("pl-minutes-km", () => JSON.stringify({ minutes: 45, distanceKm: 8, focus: "Easy" }));
    expect(p.r.success).toBe(true);
    const invented = await run("pl-no-numbers", () => JSON.stringify({ minutes: 30 }));
    expect(invented.r.gatesPass).toBe(false);
    const l = await run("lp-unrelated", () => JSON.stringify({ changed: true, equipment: "A new rack." }));
    expect(l.r.gatesPass).toBe(false);
    const l2 = await run("lp-unrelated", () => JSON.stringify({ changed: false, equipment: "" }));
    expect(l2.r.gatesPass).toBe(true);
  });

  it("an HTTP failure ends on the fallback and is counted", async () => {
    const f = (async () => new Response("boom", { status: 500 })) as unknown as typeof fetch;
    const r = await runOne(one("bs-home-dumbbells-only"), 1, setupProvider(ENV, f), new Budget(50), opts);
    expect(r.status).toBe("done");
    expect(r.fallback).toBe(true);
    expect(r.gatesPass).toBe(false);
  });
});

describe("provider setup", () => {
  it("EVAL_MODEL and EVAL_PROVIDER override the env; a missing provider or key is an error", async () => {
    const s = stub(() => plan("a", "b", "c"));
    const setup = setupProvider({ ...ENV, EVAL_MODEL: "cheap-model" }, s.f);
    expect(setup.model).toBe("cheap-model");
    await runOne(one("bs-home-dumbbells-only"), 1, setup, new Budget(5), opts);
    expect(s.bodies[0].model).toBe("cheap-model");
    expect(setupProvider({ ...ENV, AI_PROVIDER: "none", EVAL_PROVIDER: "mock" }).provider).toBe("mock");
    expect(() => setupProvider({})).toThrow(/AI_PROVIDER/);
    expect(() => setupProvider({ AI_PROVIDER: "openai" })).toThrow(/OPENAI_API_KEY/);
  });
});

describe("budget", () => {
  it("stops the run: never more provider calls than --max-calls, the rest is marked", async () => {
    const s = stub(() => plan("a", "b", "c"));
    const cases = selectCases({ job: "build_session" });
    const { runs, budget } = await runAll(cases, setupProvider(ENV, s.f), { ...opts, maxCalls: 3 });
    expect(s.bodies.length).toBeLessThanOrEqual(3);
    expect(budget.used).toBe(s.bodies.length);
    expect(budget.spent).toBe(true);
    expect(runs).toHaveLength(cases.length);
    expect(runs.filter((r) => r.status === "done").length).toBeLessThanOrEqual(3);
    expect(runs.some((r) => r.status === "skipped")).toBe(true);
    const done = aggregate(runs)[0]!;
    expect(done.runs).toBe(runs.filter((r) => r.status === "done").length); // skipped runs stay out of the rates
  });

  it("a case that hits the cap in the middle is aborted, not scored", async () => {
    const s = stub(() => "Fine.");
    const r = await runOne(one("ch-declined-advice"), 1, setupProvider(ENV, s.f), new Budget(1), opts); // two turns, one call
    expect(r.status).toBe("aborted");
    expect(s.bodies).toHaveLength(1);
  });

  it("samples repeat every case and concurrency does not break the count", async () => {
    const s = stub(() => JSON.stringify({ changed: false, equipment: "" }));
    const { runs } = await runAll(selectCases({ job: "learn_place" }), setupProvider(ENV, s.f), { ...opts, samples: 3, concurrency: 4 });
    expect(runs).toHaveLength(12);
    expect(new Set(runs.map((r) => `${r.caseId}#${r.sample}`)).size).toBe(12);
  });
});

describe("the whole set against the mock provider and the reports", () => {
  it("runs every case, writes the json and the markdown, and keeps the shape", async () => {
    const { runs, budget } = await runAll(CASES, setupProvider({ AI_PROVIDER: "mock" }), { ...opts, concurrency: 4 });
    expect(runs).toHaveLength(CASES.length);
    expect(runs.every((r) => r.status === "done")).toBe(true);
    const dir = mkdtempSync(join(tmpdir(), "evals-"));
    try {
      const meta = { provider: "mock", model: "mock/x y", startedAt: "2026-11-18T09:00:00Z", samples: 1, calls: budget.used, maxCalls: 50 };
      const files = writeReports(dir, meta, runs);
      expect(readdirSync(dir).sort()).toEqual(["2026-11-18T09-00-00Z-mock_x_y.json", "2026-11-18T09-00-00Z-mock_x_y.md"]);
      const json = JSON.parse(readFileSync(files.json, "utf8"));
      expect(json.runs).toHaveLength(CASES.length);
      expect(Object.keys(json.runs[0]).sort()).toEqual(expect.arrayContaining(["caseId", "input", "raw", "final", "gates", "expect", "ms", "promptTokens", "completionTokens"]));
      const md = readFileSync(files.md, "utf8");
      expect(md).toContain("| job | runs | gate pass %");
      expect(md).toContain("## Failed cases");
      expect(md).toContain("bs-named-no-note"); // the mock plan has two exercises: the size expectation fails
      expect(markdown(meta, runs)).toBe(md);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe("rules of the framework", () => {
  it("the evals code never imports the Convex server runtime or a database", () => {
    const root = join(__dirname, "..", "evals");
    const files = (d: string): string[] => readdirSync(d, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? files(join(d, e.name)) : e.name.endsWith(".ts") ? [join(d, e.name)] : []));
    for (const f of files(root)) expect(readFileSync(f, "utf8"), f).not.toMatch(/_generated|convex-test|from "convex\/server"/);
  });

  it("flags are read and bad ones are refused", () => {
    expect(parseArgs([])).toMatchObject({ samples: 1, concurrency: 4, maxCalls: 150 });
    expect(parseArgs(["--samples", "3", "--job", "chat", "--case", "x", "--concurrency", "2", "--max-calls", "9"])).toMatchObject({ samples: 3, job: "chat", caseId: "x", concurrency: 2, maxCalls: 9 });
    expect(() => parseArgs(["--samples", "0"])).toThrow();
    expect(() => parseArgs(["--job", "nope"])).toThrow();
    expect(() => parseArgs(["--wat"])).toThrow();
    expect(() => selectCases({ caseId: "nope" })).toThrow();
  });
});
