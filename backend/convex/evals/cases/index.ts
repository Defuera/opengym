import type { EvalCase } from "../types";
import { buildCases } from "./buildSession";
import { chatCases } from "./chat";
import { learnCases } from "./learnPlace";
import { parseCases } from "./parseLog";

export const CASES: EvalCase[] = [...buildCases, ...chatCases, ...parseCases, ...learnCases];

export function selectCases(opts: { job?: string; caseId?: string }): EvalCase[] {
  const out = CASES.filter((c) => (!opts.job || c.job === opts.job) && (!opts.caseId || c.id === opts.caseId));
  if (out.length === 0) throw new Error(`no case matches job=${opts.job ?? "*"} case=${opts.caseId ?? "*"}`);
  return out;
}
