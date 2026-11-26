import { describe, expect, it } from "vitest";
import type { Usage } from "../functions/model/ai/provider";
import { AnthropicProvider } from "../functions/model/ai/providers/anthropic";
import { createDeepSeekProvider } from "../functions/model/ai/providers/deepseek";
import { createOpenAiProvider } from "../functions/model/ai/providers/openai";
import { anthropicUsage, chatUsage, imageUsage, reportUsage, sumUsage, transcribeUsage } from "../functions/model/ai/usage";

const stub = (reply: unknown, status = 200) => (async () => new Response(JSON.stringify(reply), { status })) as unknown as typeof fetch;
const req = { system: "S", messages: [{ role: "user" as const, content: "hi" }], json: false, maxTokens: 10 };

describe("usage parsers", () => {
  it("reads chat-completions fields", () => {
    expect(chatUsage({ prompt_tokens: 10, completion_tokens: 4, prompt_tokens_details: { cached_tokens: 6 }, completion_tokens_details: { reasoning_tokens: 3 } })).toEqual({ inputTokens: 10, outputTokens: 4, cachedInputTokens: 6, reasoningTokens: 3 });
  });
  it("reads responses-style fields", () => {
    expect(chatUsage({ input_tokens: 9, output_tokens: 2, input_tokens_details: { cached_tokens: 1 }, output_tokens_details: { reasoning_tokens: 1 } })).toEqual({ inputTokens: 9, outputTokens: 2, cachedInputTokens: 1, reasoningTokens: 1 });
  });
  it("reads the deepseek cache hit field", () => {
    expect(chatUsage({ prompt_tokens: 10, completion_tokens: 1, prompt_cache_hit_tokens: 8 })).toMatchObject({ cachedInputTokens: 8 });
  });
  it("keeps a missing field absent and gives nothing for no usage", () => {
    expect(chatUsage({ prompt_tokens: 5 })).toEqual({ inputTokens: 5 });
    expect(chatUsage({})).toBeUndefined();
    expect(chatUsage(undefined)).toBeUndefined();
    expect(chatUsage({ prompt_tokens: "5", completion_tokens: -1 })).toBeUndefined();
  });
  it("adds the anthropic cache parts to the input", () => {
    expect(anthropicUsage({ input_tokens: 10, cache_read_input_tokens: 5, cache_creation_input_tokens: 2, output_tokens: 7 })).toEqual({ inputTokens: 17, cachedInputTokens: 5, outputTokens: 7 });
    expect(anthropicUsage({ output_tokens: 7 })).toEqual({ outputTokens: 7 });
  });
  it("reads transcribe usage as tokens or as seconds", () => {
    expect(transcribeUsage({ text: "x", usage: { type: "tokens", input_tokens: 20, output_tokens: 5, total_tokens: 25 } })).toEqual({ inputTokens: 20, outputTokens: 5 });
    expect(transcribeUsage({ text: "x", usage: { type: "duration", seconds: 12 } })).toEqual({ audioSeconds: 12 });
    expect(transcribeUsage({ text: "x" })).toBeUndefined();
  });
  it("reads image usage", () => {
    expect(imageUsage({ data: [{}, {}], usage: { input_tokens: 3, output_tokens: 4 } }, { spec: "s", inputImages: 2 })).toEqual({ inputTokens: 3, outputTokens: 4, images: 2, imageSpec: "s", inputImages: 2 });
    expect(imageUsage({}, { spec: "s", inputImages: 0 })).toEqual({ imageSpec: "s", inputImages: 0 });
  });
  it("sums only what was reported", () => {
    expect(sumUsage([{ inputTokens: 1, outputTokens: 2 }, undefined, { inputTokens: 3 }])).toEqual({ inputTokens: 4, outputTokens: 2 });
    expect(sumUsage([])).toEqual({});
  });
  it("a hook that throws does not fail the call", () => {
    expect(() => reportUsage({ onUsage: () => { throw new Error("x"); } }, { inputTokens: 1 })).not.toThrow();
  });
});

describe("providers report usage", () => {
  it("openai chat, also when the reply is empty", async () => {
    const got: Usage[] = [];
    const p = createOpenAiProvider({ apiKey: "K", model: "M", fetch: stub({ choices: [{ message: { content: "ok" } }], usage: { prompt_tokens: 7, completion_tokens: 2 } }) });
    expect(await p.complete({ ...req, onUsage: (u) => got.push(u) })).toBe("ok");
    expect(got).toEqual([{ inputTokens: 7, outputTokens: 2 }]);
    const empty = createOpenAiProvider({ apiKey: "K", model: "M", fetch: stub({ choices: [{ message: { content: "" } }], usage: { prompt_tokens: 7, completion_tokens: 0 } }) });
    await expect(empty.complete({ ...req, onUsage: (u) => got.push(u) })).rejects.toThrow(/empty/);
    expect(got).toHaveLength(2);
  });
  it("no usage in the answer: the hook is not called", async () => {
    const got: Usage[] = [];
    await createDeepSeekProvider({ apiKey: "K", model: "M", fetch: stub({ choices: [{ message: { content: "ok" } }] }) }).complete({ ...req, onUsage: (u) => got.push(u) });
    expect(got).toEqual([]);
  });
  it("an HTTP error reports nothing", async () => {
    const got: Usage[] = [];
    await expect(createOpenAiProvider({ apiKey: "K", model: "M", fetch: stub({}, 500) }).complete({ ...req, onUsage: (u) => got.push(u) })).rejects.toThrow(/HTTP 500/);
    expect(got).toEqual([]);
  });
  it("anthropic chat", async () => {
    const got: Usage[] = [];
    const p = new AnthropicProvider({ apiKey: "K", model: "M", fetch: stub({ content: [{ type: "text", text: "ok" }], usage: { input_tokens: 4, output_tokens: 1 } }) });
    await p.complete({ ...req, onUsage: (u) => got.push(u) });
    expect(got).toEqual([{ inputTokens: 4, outputTokens: 1 }]);
    expect(p.model).toBe("M");
  });
  it("openai transcribe and image", async () => {
    const got: Usage[] = [];
    const t = createOpenAiProvider({ apiKey: "K", model: "M", transcribeModel: "T", fetch: stub({ text: "hello", usage: { type: "tokens", input_tokens: 30, output_tokens: 3 } }) });
    expect(await t.transcribe!(new Uint8Array(4), "audio/mp4", "a.m4a", { onUsage: (u) => got.push(u) })).toBe("hello");
    expect(t.transcribeModel).toBe("T");
    const i = createOpenAiProvider({ apiKey: "K", model: "M", fetch: stub({ data: [{ b64_json: btoa("PNG") }], usage: { input_tokens: 50, output_tokens: 900 } }) });
    await i.image!("draw", [{ bytes: new Uint8Array(2), mime: "image/jpeg" }], { onUsage: (u) => got.push(u) });
    expect(got).toEqual([{ inputTokens: 30, outputTokens: 3 }, { inputTokens: 50, outputTokens: 900, images: 1, imageSpec: "1536x1024 medium", inputImages: 1 }]);
  });
});
