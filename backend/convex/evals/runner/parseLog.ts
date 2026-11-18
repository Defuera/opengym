import { type ParsedLog, parseLogJob, structureOf } from "../../functions/model/ai/jobs/parseLog";
import { type Logger, runJob } from "../../functions/model/ai/runJob";
import { localDay } from "../../functions/model/logDate";
import { buildParseLogInput } from "../../functions/model/parseLogInput";
import type { Exercise } from "../../functions/model/schema";
import { activityKey } from "../../functions/model/sessionShape";
import type { ParseSubject } from "../assertions/subject";
import { NOW, persona } from "../fixtures";
import type { ParseCase } from "../types";
import type { CaseOutput, RunCtx } from "./types";

const silent: Logger = { info() {}, warn() {}, error() {} };

/** parse_log as the server does it: the input from the log, runJob, then structureOf (the day, the usual sets, the rounding). */
export async function runParseLog(c: ParseCase, ctx: RunCtx): Promise<CaseOutput> {
  const p = persona(c.persona);
  const i = buildParseLogInput(p.sessions, { type: c.activity, startedAt: NOW }, c.text, NOW);
  const r = await runJob(parseLogJob, i.job, ctx.provider, silent, { timeoutMs: ctx.timeoutMs });
  const usual = new Map(i.usual.map((e) => [activityKey(e.name), e as Exercise]));
  const found = structureOf(r.value as ParsedLog, usual, i.at, i.now);
  const day = localDay(found.startedAt ?? i.at, "UTC");
  const subject: ParseSubject = { job: "parse_log", text: c.text, parsed: r.value, found, day, now: NOW };
  return { subject, paths: [r.path], fallbackReasons: r.reason ? [r.reason] : [], final: { day, ...found } };
}
