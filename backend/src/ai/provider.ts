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
}

export interface HttpProviderOptions {
  apiKey: string;
  model: string;
  baseUrl?: string;
  timeoutMs?: number;
  fetch?: typeof fetch;
}

export class ProviderError extends Error {}

/** POST JSON with a timeout; throws ProviderError on non-2xx or timeout. */
export async function postJson(
  f: typeof fetch,
  url: string,
  headers: Record<string, string>,
  body: unknown,
  timeoutMs: number,
): Promise<unknown> {
  let res: Response;
  try {
    res = await f(url, {
      method: "POST",
      headers: { "content-type": "application/json", ...headers },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (e) {
    const err = e as Error;
    if (err.name === "TimeoutError" || err.name === "AbortError") {
      throw new ProviderError(`request timed out after ${timeoutMs} ms`);
    }
    throw new ProviderError(`request failed: ${err.message}`);
  }
  const text = await res.text();
  if (!res.ok) throw new ProviderError(`HTTP ${res.status}: ${text.slice(0, 300)}`);
  try {
    return JSON.parse(text);
  } catch {
    throw new ProviderError("response was not JSON");
  }
}
