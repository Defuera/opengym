import { describe, expect, it } from "vitest";
import { ConfigError, createProviderFromEnv } from "../src/ai/factory";
import { AnthropicProvider } from "../src/ai/providers/anthropic";
import { createDeepSeekProvider } from "../src/ai/providers/deepseek";
import { createOpenAiProvider } from "../src/ai/providers/openai";

function stub(reply: unknown) {
  const calls: { url: string; init: RequestInit; body: any }[] = []; // eslint-disable-line @typescript-eslint/no-explicit-any
  const f = (async (url: string, init: RequestInit) => {
    calls.push({ url, init, body: JSON.parse(init.body as string) });
    return new Response(JSON.stringify(reply), { status: 200 });
  }) as unknown as typeof fetch;
  return { f, calls };
}

const req = { system: "SYS", messages: [{ role: "user" as const, content: "hi" }], json: true, maxTokens: 100 };
const img = { mime: "image/png", base64: "AAAA" };

describe("provider adapters", () => {
  it("anthropic request shape", async () => {
    const { f, calls } = stub({ content: [{ type: "text", text: "ok" }] });
    const p = new AnthropicProvider({ apiKey: "K", model: "M", fetch: f });
    expect(await p.complete({ ...req, images: [img] })).toBe("ok");
    const c = calls[0]!;
    expect(c.url).toBe("https://api.anthropic.com/v1/messages");
    expect(c.init.headers).toMatchObject({ "x-api-key": "K", "anthropic-version": "2023-06-01" });
    expect(c.body).toMatchObject({ model: "M", max_tokens: 100, system: "SYS" });
    expect(c.body.messages[0].content).toEqual([
      { type: "image", source: { type: "base64", media_type: "image/png", data: "AAAA" } },
      { type: "text", text: "hi" },
    ]);
    expect(c.init.signal).toBeDefined();
  });

  it("openai request shape", async () => {
    const { f, calls } = stub({ choices: [{ message: { content: "ok" } }] });
    const p = createOpenAiProvider({ apiKey: "K", model: "M", fetch: f, baseUrl: "http://local:1" });
    expect(await p.complete({ ...req, images: [img] })).toBe("ok");
    const c = calls[0]!;
    expect(c.url).toBe("http://local:1/v1/chat/completions");
    expect(c.init.headers).toMatchObject({ authorization: "Bearer K" });
    expect(c.body.model).toBe("M");
    expect(c.body.response_format).toEqual({ type: "json_object" });
    expect(c.body.messages[0]).toEqual({ role: "system", content: "SYS" });
    expect(c.body.messages[1].content).toEqual([
      { type: "text", text: "hi" },
      { type: "image_url", image_url: { url: "data:image/png;base64,AAAA" } },
    ]);
    await p.complete({ ...req, json: false });
    expect(calls[1]!.body.response_format).toBeUndefined();
  });

  it("deepseek request shape, no images", async () => {
    const { f, calls } = stub({ choices: [{ message: { content: "ok" } }] });
    const p = createDeepSeekProvider({ apiKey: "K", model: "M", fetch: f });
    expect(p.supportsImages).toBe(false);
    await p.complete({ ...req, images: [img] });
    const c = calls[0]!;
    expect(c.url).toBe("https://api.deepseek.com/chat/completions");
    expect(c.body.max_tokens).toBe(100);
    expect(c.body.messages[1]).toEqual({ role: "user", content: "hi" });
  });

  it("errors on HTTP failure", async () => {
    const f = (async () => new Response("nope", { status: 500 })) as unknown as typeof fetch;
    await expect(new AnthropicProvider({ apiKey: "K", model: "M", fetch: f }).complete(req)).rejects.toThrow(/HTTP 500/);
  });

  it("factory demands key and model except for mock/none", () => {
    expect(createProviderFromEnv({ AI_PROVIDER: "mock" })?.name).toBe("mock");
    expect(createProviderFromEnv({})).toBeNull();
    expect(() => createProviderFromEnv({ AI_PROVIDER: "anthropic" })).toThrow(ConfigError);
    expect(() => createProviderFromEnv({ AI_PROVIDER: "openai", OPENAI_API_KEY: "k" })).toThrow(/OPENAI_MODEL/);
    expect(createProviderFromEnv({ AI_PROVIDER: "deepseek", DEEPSEEK_API_KEY: "k", DEEPSEEK_MODEL: "m" })?.name).toBe("deepseek");
    expect(() => createProviderFromEnv({ AI_PROVIDER: "x" })).toThrow(/not one of/);
  });
});
