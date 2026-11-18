import { evaluateAll, implicitGates } from "../assertions";
import type { EvalCase } from "../types";
import { BUDGET_ERROR, Budget } from "./budget";
import { runBuildSession } from "./buildSession";
import { runChat } from "./chat";
import { runLearnPlace } from "./learnPlace";
import { runParseLog } from "./parseLog";
import { type ProviderSetup } from "./provider";
import { type CaseOutput, type CaseRun, CallRecorder, type RunCtx } from "./types";

export interface RunOptions {
  samples: number;
  concurrency: number;
  maxCalls: number;
  timeoutMs: number;
  /** USD per million tokens, when known. */
  price?: { in: number; out: number };
  onDone?(run: CaseRun, done: number, total: number): void;
}

/** What the report shows of a case's input: the pieces the person gave, not the checks. */
export function inputSummary(c: EvalCase): unknown {
  switch (c.job) {
    case "build_session":
      return { persona: c.persona, name: c.name, text: c.text, feedback: c.feedback, previousPlan: c.previousPlan ? "(a plan with exercises)" : undefined, placeText: c.placeText };
    case "chat":
      return { persona: c.persona, turns: c.turns, place: c.place };
    case "parse_log":
      return { persona: c.persona, activity: c.activity, text: c.text };
    case "learn_place":
      return { persona: c.persona, place: c.place, sentences: c.sentences };
  }
}

function pipeline(c: EvalCase, ctx: RunCtx): Promise<CaseOutput> {
  switch (c.job) {
    case "build_session":
      return runBuildSession(c, ctx);
    case "chat":
      return runChat(c, ctx);
    case "parse_log":
      return runParseLog(c, ctx);
    case "learn_place":
      return runLearnPlace(c, ctx);
  }
}

const blank = (c: EvalCase, sample: number, status: CaseRun["status"], error?: string): CaseRun => ({
  caseId: c.id, job: c.job, family: c.family, sample, status, ...(error ? { error } : {}), input: inputSummary(c), raw: [], final: null, paths: [], fallback: false, retried: false,
  calls: 0, ms: 0, promptTokens: 0, completionTokens: 0, gates: [], expect: [], warn: [], gatesPass: false, success: false,
});

/** One case, one sample. Never throws: an error ends in status "error"; a spent budget in "aborted". */
export async function runOne(c: EvalCase, sample: number, setup: ProviderSetup, budget: Budget, opts: RunOptions): Promise<CaseRun> {
  const rec = new CallRecorder();
  const t0 = Date.now();
  const run = blank(c, sample, "done");
  try {
    const out = await pipeline(c, { provider: setup.make(rec, budget), rec, timeoutMs: opts.timeoutMs });
    const gates = [...implicitGates(out.subject, out.paths), ...evaluateAll(c.gates, out.subject)];
    const expect = evaluateAll(c.expect, out.subject);
    Object.assign(run, { final: out.final, paths: out.paths, fallback: out.paths.includes("fallback"), retried: rec.calls.length > out.paths.length, gates, expect, warn: evaluateAll(c.warn ?? [], out.subject) });
    run.gatesPass = gates.every((g) => g.pass);
    run.success = run.gatesPass && expect.every((e) => e.pass);
    if (out.fallbackReasons.length) run.error = out.fallbackReasons.join(" | ");
  } catch (e) {
    run.status = "error";
    run.error = (e as Error).message;
  }
  if (rec.calls.some((x) => x.error === BUDGET_ERROR)) {
    run.status = "aborted";
    run.error = BUDGET_ERROR;
  }
  run.raw = rec.calls.flatMap((x) => (x.raw !== undefined ? [x.raw] : []));
  run.calls = rec.calls.filter((x) => x.error !== BUDGET_ERROR).length;
  run.ms = Date.now() - t0;
  run.promptTokens = rec.calls.reduce((n, x) => n + (x.promptTokens ?? 0), 0);
  run.completionTokens = rec.calls.reduce((n, x) => n + (x.completionTokens ?? 0), 0);
  if (opts.price) run.costUsd = (run.promptTokens * opts.price.in + run.completionTokens * opts.price.out) / 1_000_000;
  return run;
}

/** Every (sample, case) with a small worker pool. Stops starting new work when the call budget is spent; the rest is "skipped". */
export async function runAll(cases: EvalCase[], setup: ProviderSetup, opts: RunOptions): Promise<{ runs: CaseRun[]; budget: Budget }> {
  const budget = new Budget(opts.maxCalls);
  const tasks = Array.from({ length: opts.samples }, (_, s) => cases.map((c) => ({ c, sample: s + 1 }))).flat();
  const runs: CaseRun[] = new Array(tasks.length);
  let next = 0;
  let done = 0;
  const worker = async () => {
    for (let i = next++; i < tasks.length; i = next++) {
      const { c, sample } = tasks[i]!;
      runs[i] = budget.spent ? blank(c, sample, "skipped", "budget spent before this case started") : await runOne(c, sample, setup, budget, opts);
      opts.onDone?.(runs[i]!, ++done, tasks.length);
    }
  };
  await Promise.all(Array.from({ length: Math.max(1, Math.min(opts.concurrency, tasks.length)) }, worker));
  return { runs, budget };
}
