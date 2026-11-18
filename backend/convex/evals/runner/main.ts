import { fileURLToPath } from "node:url";
import { selectCases } from "../cases";
import { aggregate } from "../reporting/summary";
import { writeReports } from "../reporting/write";
import { USAGE, parseArgs } from "./args";
import { setupProvider } from "./provider";
import { runAll } from "./run";

/** `npm run eval`: a live pass over the cases with the real jobs. Everything stays in memory; nothing touches a database. */
async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) return void console.log(USAGE);
  const cases = selectCases({ job: args.job, caseId: args.caseId });
  const setup = setupProvider(process.env);
  const price = process.env.EVAL_PRICE_IN && process.env.EVAL_PRICE_OUT ? { in: Number(process.env.EVAL_PRICE_IN), out: Number(process.env.EVAL_PRICE_OUT) } : undefined;
  const startedAt = new Date().toISOString().replace(/\.\d+Z$/, "Z");
  console.log(`eval: ${cases.length} cases x ${args.samples} sample(s), ${setup.provider} / ${setup.model}, at most ${args.maxCalls} calls`);
  const { runs, budget } = await runAll(cases, setup, {
    ...args,
    price,
    onDone: (r, n, total) => console.log(`[${n}/${total}] ${r.caseId} #${r.sample} ${r.status === "done" ? (r.success ? "ok" : r.gatesPass ? "task not met" : "GATE FAILED") : r.status} ${r.ms} ms`),
  });
  const files = writeReports(args.outDir ?? fileURLToPath(new URL("../reports/", import.meta.url)), { provider: setup.provider, model: setup.model, startedAt, samples: args.samples, calls: budget.used, maxCalls: args.maxCalls }, runs);
  for (const s of aggregate(runs)) console.log(`${s.job}: gates ${s.gatePass}%, success ${s.success}%, fallback ${s.fallback}%, retry ${s.retry}%, ${s.avgMs} ms avg`);
  if (budget.spent) console.log(`The call budget (${args.maxCalls}) is spent; unfinished cases are marked in the report.`);
  console.log(`Report: ${files.md}\n        ${files.json}`);
  process.exitCode = runs.some((r) => r.status === "done" && !r.gatesPass) ? 1 : 0;
}

main().catch((e) => {
  console.error(`eval failed: ${(e as Error).message}`);
  process.exitCode = 2;
});
