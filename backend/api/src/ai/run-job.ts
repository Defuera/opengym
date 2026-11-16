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
  build(input: I): Prompt;
  fallback(input: I): O;
}

export interface JobResult<O> {
  value: O;
  path: "ai" | "fallback";
  /** Why the fallback was used, when it was. */
  reason?: string;
}

export interface RunOptions {
  timeoutMs?: number;
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
  const useFallback = (reason: string): JobResult<O> => {
    logger.info(`[ai] job=${job.name} path=fallback reason="${reason}" ms=${Date.now() - started}`);
    return { value: job.fallback(input), path: "fallback", reason };
  };
  if (!provider) return useFallback("AI is not configured");

  const prompt = job.build(input);
  const images = prompt.images?.length && provider.supportsImages ? prompt.images : undefined;
  let messages = prompt.messages;
  let lastError = "unknown";
  const deadline = opts.timeoutMs ? started + opts.timeoutMs : null;

  for (let attempt = 0; attempt < 2; attempt++) {
    const remaining = deadline ? deadline - Date.now() : undefined;
    if (remaining !== undefined && remaining <= 0) break;
    try {
      const raw = await provider.complete({
        system: prompt.system,
        messages,
        images,
        json: job.json,
        maxTokens: job.maxTokens,
        timeoutMs: remaining,
      });
      const parsed = job.json ? extractJson(raw) : raw.trim();
      const result = job.output.safeParse(parsed);
      if (result.success) {
        logger.info(`[ai] job=${job.name} path=ai provider=${provider.name} attempt=${attempt + 1} ms=${Date.now() - started}`);
        return { value: result.data, path: "ai" };
      }
      lastError = `invalid output: ${result.error.issues.slice(0, 3).map((i) => `${i.path.join(".")} ${i.message}`).join("; ")}`;
      messages = [
        ...prompt.messages,
        { role: "assistant", content: raw.slice(0, 2000) },
        { role: "user", content: job.json ? `That reply was invalid (${lastError}). Reply again with only valid JSON in the required shape.` : "That reply was empty. Reply again." },
      ];
    } catch (e) {
      lastError = (e as Error).message;
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
