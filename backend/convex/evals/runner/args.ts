export interface Args {
  samples: number;
  job?: string;
  caseId?: string;
  concurrency: number;
  maxCalls: number;
  timeoutMs: number;
  outDir?: string;
  help: boolean;
}

export const USAGE = `Usage: npm run eval -- [options]
  --samples N        answers per case (default 1)
  --job NAME         build_session | chat | parse_log | learn_place
  --case ID          one case
  --concurrency N    cases at the same time (default 4)
  --max-calls N      hard cap on provider calls, retries included (default 150)
  --timeout MS       time budget of one job call (default 25000, the server's)
  --out DIR          report folder (default evals/reports)
Env: AI_PROVIDER (or EVAL_PROVIDER), <PROVIDER>_API_KEY, <PROVIDER>_MODEL (or EVAL_MODEL),
     EVAL_PRICE_IN / EVAL_PRICE_OUT (USD per million tokens, optional, for the cost line).`;

const JOBS = ["build_session", "chat", "parse_log", "learn_place"];

/** Reads the flags. Throws a short message on a bad one. */
export function parseArgs(argv: string[]): Args {
  const a: Args = { samples: 1, concurrency: 4, maxCalls: 150, timeoutMs: 25_000, help: false };
  const int = (flag: string, v: string | undefined, min: number): number => {
    const n = Number(v);
    if (!Number.isInteger(n) || n < min) throw new Error(`${flag} needs a whole number of at least ${min}`);
    return n;
  };
  for (let i = 0; i < argv.length; i++) {
    const f = argv[i]!;
    const v = argv[i + 1];
    if (f === "--help" || f === "-h") a.help = true;
    else if (f === "--samples") a.samples = int(f, argv[++i], 1);
    else if (f === "--concurrency") a.concurrency = int(f, argv[++i], 1);
    else if (f === "--max-calls") a.maxCalls = int(f, argv[++i], 1);
    else if (f === "--timeout") a.timeoutMs = int(f, argv[++i], 1);
    else if (f === "--job") {
      if (!v || !JOBS.includes(v)) throw new Error(`--job must be one of ${JOBS.join(", ")}`);
      a.job = argv[++i];
    } else if (f === "--case") {
      if (!v) throw new Error("--case needs an id");
      a.caseId = argv[++i];
    } else if (f === "--out") {
      if (!v) throw new Error("--out needs a folder");
      a.outDir = argv[++i];
    } else throw new Error(`unknown option ${f}`);
  }
  return a;
}
