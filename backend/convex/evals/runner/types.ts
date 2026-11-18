import type { CheckResult } from "../assertions";
import type { Subject } from "../assertions/subject";
import type { AiProvider } from "../../functions/model/ai/provider";

export interface CallRecord {
  ms: number;
  raw?: string;
  error?: string;
  promptTokens?: number;
  completionTokens?: number;
}

/** The calls of one case. A call that the provider adapter made is recorded with its time and the usage the provider gave back. */
export class CallRecorder {
  calls: CallRecord[] = [];
  /** Set by the fetch wrapper from the response; read by the next recorded call. */
  usage: { promptTokens?: number; completionTokens?: number } = {};
}

/** What a pipeline gets: the provider (null never happens in a live run), the recorder and the time budget for a job. */
export interface RunCtx {
  provider: AiProvider;
  rec: CallRecorder;
  timeoutMs: number;
}

/** What a pipeline returns: the subject the checks read, and the facts for the report. */
export interface CaseOutput {
  subject: Subject;
  /** One entry per runJob call (a chat turn is one). */
  paths: ("ai" | "fallback")[];
  fallbackReasons: string[];
  /** What the user would see, for the report. */
  final: unknown;
}

export type RunStatus = "done" | "error" | "aborted" | "skipped";

export interface CaseRun {
  caseId: string;
  job: string;
  family: string;
  sample: number;
  status: RunStatus;
  error?: string;
  input: unknown;
  /** Every raw model answer of the case, in order. */
  raw: string[];
  final: unknown;
  paths: ("ai" | "fallback")[];
  fallback: boolean;
  retried: boolean;
  calls: number;
  ms: number;
  promptTokens: number;
  completionTokens: number;
  costUsd?: number;
  gates: CheckResult[];
  expect: CheckResult[];
  warn: CheckResult[];
  gatesPass: boolean;
  success: boolean;
}
