import type { CaseRun } from "../runner/types";
import { excerpt } from "../assertions/text";

export interface JobStats {
  job: string;
  runs: number;
  gatePass: number;
  success: number;
  fallback: number;
  retry: number;
  avgMs: number;
  promptTokens: number;
  completionTokens: number;
  costUsd?: number;
}

const pct = (n: number, d: number): number => (d === 0 ? 0 : Math.round((n / d) * 1000) / 10);

/** Per job: the four numbers in the design's order. Runs that did not finish (error, aborted, skipped) are left out of the rates and counted apart. */
export function aggregate(runs: CaseRun[]): JobStats[] {
  const jobs = [...new Set(runs.map((r) => r.job))];
  return jobs.map((job) => {
    const done = runs.filter((r) => r.job === job && r.status === "done");
    const cost = done.filter((r) => r.costUsd !== undefined);
    return {
      job,
      runs: done.length,
      gatePass: pct(done.filter((r) => r.gatesPass).length, done.length),
      success: pct(done.filter((r) => r.success).length, done.length),
      fallback: pct(done.filter((r) => r.fallback).length, done.length),
      retry: pct(done.filter((r) => r.retried).length, done.length),
      avgMs: done.length ? Math.round(done.reduce((n, r) => n + r.ms, 0) / done.length) : 0,
      promptTokens: done.reduce((n, r) => n + r.promptTokens, 0),
      completionTokens: done.reduce((n, r) => n + r.completionTokens, 0),
      ...(cost.length ? { costUsd: Math.round(cost.reduce((n, r) => n + (r.costUsd ?? 0), 0) * 10000) / 10000 } : {}),
    };
  });
}

/** The first failing checks of a run, as short report lines. */
function why(r: CaseRun): string[] {
  if (r.status !== "done") return [`${r.status}: ${r.error ?? ""}`];
  const bad = [...r.gates.map((x) => ({ ...x, kind: "GATE" })), ...r.expect.map((x) => ({ ...x, kind: "expect" }))].filter((x) => !x.pass);
  return bad.map((x) => `${x.kind} ${x.name}: ${x.reason}`);
}

/** The Markdown summary: the table per job, then every failed case with the reason and a short excerpt of the output. */
export function markdown(meta: { model: string; provider: string; startedAt: string; samples: number; calls: number; maxCalls: number }, runs: CaseRun[]): string {
  const stats = aggregate(runs);
  const out: string[] = [`# Eval run: ${meta.provider} / ${meta.model}`, "", `Started ${meta.startedAt}. ${runs.length} runs, ${meta.samples} sample(s) per case. Provider calls: ${meta.calls} of ${meta.maxCalls}.`, ""];
  out.push("| job | runs | gate pass % | task success % | fallback % | retry % | avg ms | tokens in/out | cost USD |", "|---|---|---|---|---|---|---|---|---|");
  for (const s of stats) out.push(`| ${s.job} | ${s.runs} | ${s.gatePass} | ${s.success} | ${s.fallback} | ${s.retry} | ${s.avgMs} | ${s.promptTokens}/${s.completionTokens} | ${s.costUsd ?? "n/a"} |`);
  const unfinished = runs.filter((r) => r.status !== "done");
  if (unfinished.length) out.push("", `Not finished (left out of the rates): ${unfinished.length} (${["error", "aborted", "skipped"].map((k) => `${unfinished.filter((r) => r.status === k).length} ${k}`).join(", ")}).`);
  const failed = runs.filter((r) => r.status !== "done" || !r.success);
  out.push("", `## Failed cases (${failed.length})`, "");
  if (failed.length === 0) out.push("None.");
  for (const r of failed) {
    out.push(`### ${r.caseId} (${r.job}, sample ${r.sample})`, ...why(r).map((l) => `- ${l}`));
    const warns = r.warn.filter((w) => !w.pass);
    if (warns.length) out.push(...warns.map((w) => `- warning ${w.name}: ${w.reason}`));
    const last = r.raw[r.raw.length - 1];
    if (last) out.push("", "```", excerpt(last, 400), "```");
    out.push("");
  }
  return out.join("\n");
}
