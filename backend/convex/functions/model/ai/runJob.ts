import type { z } from "zod";
import type { AiProvider, ChatMessage, ImageInput } from "./provider";

export interface Logger {
  info(msg: string): void;
  warn(msg: string): void;
  error(msg: string): void;
}

export const consoleLogger: Logger = {
  info: (m) => console.log(m),
  warn: (m) => console.warn(m),
  error: (m) => console.error(m),
};

export const silentLogger: Logger = { info() {}, warn() {}, error() {} };

export interface Prompt {
  system: string;
  messages: ChatMessage[];
  images?: ImageInput[];
}

export interface JobDef<I, O> {
  name: string;
  description: string;
  /** Plain-language description of the plain-code fallback. */
  fallbackDescription: string;
  /** true: provider asked for JSON and output is parsed; false: raw text. */
  json: boolean;
  maxTokens: number;
  output: z.ZodType<O>;
  /** A rule the zod shape cannot hold (it needs the input). A string is the reason the output is invalid: same path as a shape error. */
  check?(output: O, input: I): string | null;
  build(input: I): Prompt;
  fallback(input: I): O;
}

export interface JobResult<O> {
  value: O;
  path: "ai" | "fallback";
  /** Why the fallback was used, when it was. */
  reason?: string;
}

/** One provider call of a job: the raw reply, or the error (a failed check or a failed request). */
export interface JobAttempt {
  raw?: string;
  error?: string;
  ms: number;
}

/** What one job run sent and got back: the exact prompt, every attempt, the outcome. The caller may store it (ADR-027). */
export interface JobTrace {
  job: string;
  system: string;
  messages: ChatMessage[];
  /** How many images went with the prompt (the images themselves are not kept). */
  images: number;
  attempts: JobAttempt[];
  path: "ai" | "fallback";
  reason?: string;
  ms: number;
}

export interface RunOptions {
  timeoutMs?: number;
  /** Called once per run, after the outcome is known. An error in it never changes the result. */
  onTrace?(trace: JobTrace): void;
}

export function extractJson(text: string): unknown {
  let t = text.trim();
  const fence = t.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  if (fence?.[1]) t = fence[1];
  try {
    return JSON.parse(t);
  } catch {
    const a = t.indexOf("{");
    const b = t.lastIndexOf("}");
    if (a >= 0 && b > a) return JSON.parse(t.slice(a, b + 1));
    throw new Error("no JSON object in reply");
  }
}

/** build prompt -> provider -> parse -> validate -> one retry -> fallback. */
export async function runJob<I, O>(
  job: JobDef<I, O>,
  input: I,
  provider: AiProvider | null,
  logger: Logger,
  opts: RunOptions = {},
): Promise<JobResult<O>> {
  const started = Date.now();
  const attempts: JobAttempt[] = [];
  let sent: Prompt | null = null;
  let sentImages = 0;
  const trace = (path: "ai" | "fallback", reason?: string): void => {
    if (!opts.onTrace || !sent) return;
    try {
      opts.onTrace({ job: job.name, system: sent.system, messages: sent.messages, images: sentImages, attempts, path, ...(reason ? { reason } : {}), ms: Date.now() - started });
    } catch {
      // A trace is never worth a failed job.
    }
  };
  const useFallback = (reason: string): JobResult<O> => {
    logger.info(`[ai] job=${job.name} path=fallback reason="${reason}" ms=${Date.now() - started}`);
    trace("fallback", reason);
    return { value: job.fallback(input), path: "fallback", reason };
  };
  if (!provider) return useFallback("AI is not configured");

  const prompt = job.build(input);
  const images = prompt.images?.length && provider.supportsImages ? prompt.images : undefined;
  sent = prompt;
  sentImages = images?.length ?? 0;
  let messages = prompt.messages;
  let lastError = "unknown";
  const deadline = opts.timeoutMs ? started + opts.timeoutMs : null;

  for (let attempt = 0; attempt < 2; attempt++) {
    const remaining = deadline ? deadline - Date.now() : undefined;
    if (remaining !== undefined && remaining <= 0) break;
    const attemptStarted = Date.now();
    let raw: string | undefined;
    try {
      raw = await provider.complete({
        system: prompt.system,
        messages,
        images,
        json: job.json,
        maxTokens: job.maxTokens,
        timeoutMs: remaining,
      });
      const parsed = job.json ? extractJson(raw) : raw.trim();
      const result = job.output.safeParse(parsed);
      const broken = result.success ? (job.check?.(result.data, input) ?? null) : null;
      if (result.success && !broken) {
        logger.info(`[ai] job=${job.name} path=ai provider=${provider.name} attempt=${attempt + 1} ms=${Date.now() - started}`);
        attempts.push({ raw, ms: Date.now() - attemptStarted });
        trace("ai");
        return { value: result.data, path: "ai" };
      }
      lastError = `invalid output: ${result.success ? broken : result.error.issues.slice(0, 3).map((i) => `${i.path.join(".")} ${i.message}`).join("; ")}`;
      messages = [
        ...prompt.messages,
        { role: "assistant", content: raw.slice(0, 2000) },
        { role: "user", content: job.json ? `That reply was invalid (${lastError}). Reply again with only valid JSON in the required shape.` : "That reply was empty. Reply again." },
      ];
      attempts.push({ raw, error: lastError, ms: Date.now() - attemptStarted });
    } catch (e) {
      lastError = (e as Error).message;
      attempts.push({ ...(raw !== undefined ? { raw } : {}), error: lastError, ms: Date.now() - attemptStarted });
      if (/timed out/.test(lastError)) break; // no point retrying a timeout inside a budget
    }
    logger.warn(`[ai] job=${job.name} attempt=${attempt + 1} failed: ${lastError}`);
  }
  return useFallback(lastError);
}

/** Bound to a provider and logger; what routes and services depend on. */
export interface AiRunner {
  readonly provider: AiProvider | null;
  run<I, O>(job: JobDef<I, O>, input: I, opts?: RunOptions): Promise<JobResult<O>>;
}

export function createAiRunner(provider: AiProvider | null, logger: Logger): AiRunner {
  return { provider, run: (job, input, opts) => runJob(job, input, provider, logger, opts) };
}
