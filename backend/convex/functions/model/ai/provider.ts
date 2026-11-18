export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

export interface ImageInput {
  mime: string;
  /** base64, no data: prefix */
  base64: string;
}

export interface CompleteRequest {
  system: string;
  messages: ChatMessage[];
  /** Attached to the last user message. */
  images?: ImageInput[];
  json: boolean;
  maxTokens: number;
  /** Overrides the provider's default per-call timeout. */
  timeoutMs?: number;
}

export interface AiProvider {
  readonly name: string;
  readonly supportsImages: boolean;
  complete(req: CompleteRequest): Promise<string>;
  /** Ids of the text/chat models the provider offers (see modelList.ts). Throws ProviderError on a failed request. */
  listModels(): Promise<string[]>;
  /** Speech to text. Absent on a provider that cannot do it. Throws ProviderError on a failed request. Returns the text as the provider gave it. */
  transcribe?(bytes: Uint8Array, mime: string, filename: string): Promise<string>;
}

export interface HttpProviderOptions {
  apiKey: string;
  model: string;
  baseUrl?: string;
  timeoutMs?: number;
  fetch?: typeof fetch;
  /** Model for speech to text (OpenAI only). */
  transcribeModel?: string;
}

export class ProviderError extends Error {}

/** POST JSON with a timeout; throws ProviderError on non-2xx or timeout. */
export function postJson(f: typeof fetch, url: string, headers: Record<string, string>, body: unknown, timeoutMs: number): Promise<unknown> {
  return requestJson(f, url, "POST", headers, timeoutMs, body);
}

/** POST a multipart form with a timeout and read JSON back. The content-type (with its boundary) is set by fetch. */
export function postForm(f: typeof fetch, url: string, headers: Record<string, string>, form: FormData, timeoutMs: number): Promise<unknown> {
  return requestJson(f, url, "POST", headers, timeoutMs, form);
}

/** GET JSON with a timeout; throws ProviderError on non-2xx or timeout. */
export function getJson(f: typeof fetch, url: string, headers: Record<string, string>, timeoutMs: number): Promise<unknown> {
  return requestJson(f, url, "GET", headers, timeoutMs);
}

async function requestJson(f: typeof fetch, url: string, method: "GET" | "POST", headers: Record<string, string>, timeoutMs: number, body?: unknown): Promise<unknown> {
  const isForm = typeof FormData !== "undefined" && body instanceof FormData;
  let res: Response;
  // AbortSignal.timeout is not guaranteed in the Convex runtime, so use a plain timer.
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    res = await f(url, {
      method,
      headers: isForm ? headers : { "content-type": "application/json", ...headers },
      ...(method === "POST" ? { body: isForm ? (body as FormData) : JSON.stringify(body) } : {}),
      signal: controller.signal,
    });
  } catch (e) {
    clearTimeout(timer);
    const err = e as Error;
    if (err.name === "TimeoutError" || err.name === "AbortError") {
      throw new ProviderError(`request timed out after ${timeoutMs} ms`);
    }
    throw new ProviderError(`request failed: ${err.message}`);
  }
  let text: string;
  try {
    text = await res.text();
  } catch (e) {
    throw new ProviderError(`request failed: ${(e as Error).message}`);
  } finally {
    clearTimeout(timer);
  }
  if (!res.ok) throw new ProviderError(`HTTP ${res.status}: ${text.slice(0, 300)}`);
  try {
    return JSON.parse(text);
  } catch {
    throw new ProviderError("response was not JSON");
  }
}
