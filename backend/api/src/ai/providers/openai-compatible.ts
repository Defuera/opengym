import { type AiProvider, type CompleteRequest, type HttpProviderOptions, ProviderError, postJson } from "../provider";

export interface OpenAiCompatibleConfig extends HttpProviderOptions {
  name: string;
  defaultBaseUrl: string;
  /** Path appended to the base URL. */
  path: string;
  supportsImages: boolean;
  /** OpenAI wants max_completion_tokens; DeepSeek still uses max_tokens. */
  maxTokensField: "max_completion_tokens" | "max_tokens";
}

/** Shared by the openai and deepseek providers (same wire format). */
export class OpenAiCompatibleProvider implements AiProvider {
  readonly name: string;
  readonly supportsImages: boolean;

  constructor(private readonly c: OpenAiCompatibleConfig) {
    this.name = c.name;
    this.supportsImages = c.supportsImages;
  }

  async complete(req: CompleteRequest): Promise<string> {
    const lastUser = req.messages.map((m) => m.role).lastIndexOf("user");
    const messages: unknown[] = [{ role: "system", content: req.system }];
    req.messages.forEach((m, i) => {
      if (i === lastUser && req.images?.length && this.supportsImages) {
        messages.push({
          role: m.role,
          content: [
            { type: "text", text: m.content },
            ...req.images.map((im) => ({
              type: "image_url",
              image_url: { url: `data:${im.mime};base64,${im.base64}` },
            })),
          ],
        });
      } else {
        messages.push({ role: m.role, content: m.content });
      }
    });
    const body: Record<string, unknown> = {
      model: this.c.model,
      messages,
      [this.c.maxTokensField]: req.maxTokens,
    };
    if (req.json) body.response_format = { type: "json_object" };
    const data = (await postJson(
      this.c.fetch ?? fetch,
      `${this.c.baseUrl ?? this.c.defaultBaseUrl}${this.c.path}`,
      { authorization: `Bearer ${this.c.apiKey}` },
      body,
      req.timeoutMs ?? this.c.timeoutMs ?? 30_000,
    )) as { choices?: { message?: { content?: string | null } }[] };
    const text = data.choices?.[0]?.message?.content;
    if (!text) throw new ProviderError("empty response");
    return text;
  }
}
