import { type AiProvider, type CompleteRequest, type HttpProviderOptions, ProviderError, getJson, postForm, postJson } from "../provider";
import { chatModelIds } from "../modelList";
import { type UsageHook, chatUsage, imageUsage, reportUsage, transcribeUsage } from "../usage";

export interface OpenAiCompatibleConfig extends HttpProviderOptions {
  name: string;
  defaultBaseUrl: string;
  /** Path appended to the base URL. */
  path: string;
  /** Path of the model list (GET). */
  modelsPath: string;
  supportsImages: boolean;
  /** OpenAI wants max_completion_tokens; DeepSeek still uses max_tokens. */
  maxTokensField: "max_completion_tokens" | "max_tokens";
  /** Path of speech to text (POST multipart). Without it the provider has no `transcribe`. */
  transcribePath?: string;
  /** Base path of image generation (POST), e.g. /v1/images. Without it the provider has no `image`. */
  imagePath?: string;
}

/** Image size of exercise art: two panels of 768x1024 side by side. */
const IMAGE_SIZE = "1536x1024";
const IMAGE_QUALITY = "medium";
const IMAGE_TIMEOUT_MS = 180_000;

/** Shared by the openai and deepseek providers (same wire format). */
export class OpenAiCompatibleProvider implements AiProvider {
  readonly name: string;
  readonly supportsImages: boolean;
  readonly model: string;
  readonly transcribe?: (bytes: Uint8Array, mime: string, filename: string, opts?: UsageHook) => Promise<string>;
  readonly transcribeModel?: string;
  readonly image?: (prompt: string, photos: { bytes: Uint8Array; mime: string }[], opts?: UsageHook) => Promise<Uint8Array>;
  readonly imageModel?: string;

  constructor(private readonly c: OpenAiCompatibleConfig) {
    this.name = c.name;
    this.supportsImages = c.supportsImages;
    this.model = c.model;
    if (c.transcribePath) {
      this.transcribeModel = c.transcribeModel ?? "gpt-4o-transcribe";
      this.transcribe = (bytes, mime, filename, opts) => this.speechToText(c.transcribePath!, this.transcribeModel!, bytes, mime, filename, opts);
    }
    if (c.imagePath) {
      this.imageModel = c.imageModel ?? "gpt-image-2";
      this.image = (prompt, photos, opts) => this.drawImage(c.imagePath!, this.imageModel!, prompt, photos, opts);
    }
  }

  private async drawImage(path: string, model: string, prompt: string, photos: { bytes: Uint8Array; mime: string }[], opts?: UsageHook): Promise<Uint8Array> {
    const f = this.c.fetch ?? fetch;
    const base = this.c.baseUrl ?? this.c.defaultBaseUrl;
    const auth = { authorization: `Bearer ${this.c.apiKey}` };
    let data: { data?: { b64_json?: unknown }[]; usage?: unknown };
    if (photos.length > 0) {
      const form = new FormData();
      form.append("model", model);
      form.append("prompt", prompt);
      form.append("size", IMAGE_SIZE);
      form.append("quality", IMAGE_QUALITY);
      photos.forEach((p, i) => form.append("image[]", new Blob([p.bytes as BlobPart], { type: p.mime }), `photo${i}.${p.mime.includes("png") ? "png" : "jpg"}`));
      data = (await postForm(f, `${base}${path}/edits`, auth, form, IMAGE_TIMEOUT_MS)) as typeof data;
    } else {
      data = (await postJson(f, `${base}${path}/generations`, auth, { model, prompt, size: IMAGE_SIZE, quality: IMAGE_QUALITY }, IMAGE_TIMEOUT_MS)) as typeof data;
    }
    reportUsage(opts, imageUsage(data, { spec: `${IMAGE_SIZE} ${IMAGE_QUALITY}`, inputImages: photos.length }));
    const b64 = data.data?.[0]?.b64_json;
    if (typeof b64 !== "string" || !b64) throw new ProviderError("empty image response");
    const bin = atob(b64);
    const out = new Uint8Array(bin.length);
    for (let k = 0; k < bin.length; k++) out[k] = bin.charCodeAt(k);
    return out;
  }

  private async speechToText(path: string, model: string, bytes: Uint8Array, mime: string, filename: string, opts?: UsageHook): Promise<string> {
    const form = new FormData();
    form.append("model", model);
    form.append("file", new Blob([bytes as BlobPart], { type: mime }), filename);
    const data = (await postForm(this.c.fetch ?? fetch, `${this.c.baseUrl ?? this.c.defaultBaseUrl}${path}`, { authorization: `Bearer ${this.c.apiKey}` }, form, 60_000)) as { text?: unknown };
    reportUsage(opts, transcribeUsage(data));
    return typeof data.text === "string" ? data.text : "";
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
    )) as { choices?: { message?: { content?: string | null } }[]; usage?: unknown };
    reportUsage(req, chatUsage(data.usage));
    const text = data.choices?.[0]?.message?.content;
    if (!text) throw new ProviderError("empty response");
    return text;
  }

  async listModels(): Promise<string[]> {
    const data = (await getJson(
      this.c.fetch ?? fetch,
      `${this.c.baseUrl ?? this.c.defaultBaseUrl}${this.c.modelsPath}`,
      { authorization: `Bearer ${this.c.apiKey}` },
      this.c.timeoutMs ?? 30_000,
    )) as { data?: { id?: unknown }[] };
    return chatModelIds((data.data ?? []).map((m) => m.id));
  }
}
