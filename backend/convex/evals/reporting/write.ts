import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { CaseRun } from "../runner/types";
import { aggregate, markdown } from "./summary";

export interface RunMeta {
  provider: string;
  model: string;
  startedAt: string;
  samples: number;
  calls: number;
  maxCalls: number;
}

const safe = (s: string): string => s.replace(/[^A-Za-z0-9._-]+/g, "_");

/** Writes `<timestamp>-<model>.json` (every case in full) and the `.md` summary next to it. Returns both paths. */
export function writeReports(dir: string, meta: RunMeta, runs: CaseRun[]): { json: string; md: string } {
  mkdirSync(dir, { recursive: true });
  const stem = join(dir, `${safe(meta.startedAt.replace(/:/g, "-"))}-${safe(meta.model)}`);
  writeFileSync(`${stem}.json`, JSON.stringify({ meta, summary: aggregate(runs), runs }, null, 2));
  writeFileSync(`${stem}.md`, markdown(meta, runs));
  return { json: `${stem}.json`, md: `${stem}.md` };
}
