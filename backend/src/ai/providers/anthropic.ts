import { type AiProvider, type CompleteRequest, type HttpProviderOptions, ProviderError, postJson } from "../provider";

export class AnthropicProvider implements AiProvider {
  readonly name = "anthropic";
  readonly supportsImages = true;

  constructor(private readonly o: HttpProviderOptions) {}

  async complete(req: CompleteRequest): Promise<string> {
    const lastUser = req.messages.map((m) => m.role).lastIndexOf("user");
    const messages = req.messages.map((m, i) => {
      if (i === lastUser && req.images?.length) {
        return {
          role: m.role,
          content: [
            ...req.images.map((im) => ({
              type: "image",
              source: { type: "base64", media_type: im.mime, data: im.base64 },
            })),
            { type: "text", text: m.content },
          ],
        };
      }
      return { role: m.role, content: m.content };
    });
    const url = `${this.o.baseUrl ?? "https://api.anthropic.com"}/v1/messages`;
    const data = (await postJson(
      this.o.fetch ?? fetch,
      url,
      { "x-api-key": this.o.apiKey, "anthropic-version": "2023-06-01" },
      { model: this.o.model, max_tokens: req.maxTokens, system: req.system, messages },
      req.timeoutMs ?? this.o.timeoutMs ?? 30_000,
    )) as { content?: { type: string; text?: string }[] };
    const text = (data.content ?? [])
      .filter((b) => b.type === "text")
      .map((b) => b.text ?? "")
      .join("");
    if (!text) throw new ProviderError("empty response");
    return text;
  }
}
