import { describe, expect, it } from "vitest";
import { ConfigError, createProviderFromEnv } from "../functions/model/ai/factory";
import type { AiProvider } from "../functions/model/ai/provider";
import { AnthropicProvider } from "../functions/model/ai/providers/anthropic";
import { createDeepSeekProvider } from "../functions/model/ai/providers/deepseek";
import { createOpenAiProvider } from "../functions/model/ai/providers/openai";
import { MockProvider } from "../functions/model/ai/providers/mock";
import { planSessionJob } from "../functions/model/ai/jobs/planSession";
import { buildPlanInput } from "../functions/model/ai/jobs/inputs";
import { runJob, silentLogger } from "../functions/model/ai/runJob";
import { applyPlanLimits, MAX_PLAN_EXERCISES, MAX_PLAN_SETS } from "../functions/model/rules/planner";
import type { Session } from "../functions/model/schema";

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
    expect(c.init.signal).toBeDefined();
  });

  it("openai request shape", async () => {
    const { f, calls } = stub({ choices: [{ message: { content: "ok" } }] });
    const p = createOpenAiProvider({ apiKey: "K", model: "M", fetch: f, baseUrl: "http://local:1" });
    expect(await p.complete(req)).toBe("ok");
    const c = calls[0]!;
    expect(c.url).toBe("http://local:1/v1/chat/completions");
    expect(c.init.headers).toMatchObject({ authorization: "Bearer K" });
    expect(c.body.response_format).toEqual({ type: "json_object" });
    expect(c.body.max_completion_tokens).toBe(100);
    await p.complete({ ...req, json: false });
    expect(calls[1]!.body.response_format).toBeUndefined();
  });

  it("deepseek request shape, no images", async () => {
    const { f, calls } = stub({ choices: [{ message: { content: "ok" } }] });
    const p = createDeepSeekProvider({ apiKey: "K", model: "M", fetch: f });
    expect(p.supportsImages).toBe(false);
    await p.complete({ ...req, images: [img] });
    expect(calls[0]!.url).toBe("https://api.deepseek.com/chat/completions");
    expect(calls[0]!.body.max_tokens).toBe(100);
  });

  it("errors on HTTP failure and on timeout", async () => {
    const f = (async () => new Response("nope", { status: 500 })) as unknown as typeof fetch;
    await expect(new AnthropicProvider({ apiKey: "K", model: "M", fetch: f }).complete(req)).rejects.toThrow(/HTTP 500/);
    const hang = ((_u: string, init: RequestInit) => new Promise((_r, reject) => init.signal!.addEventListener("abort", () => reject(Object.assign(new Error("aborted"), { name: "AbortError" }))))) as unknown as typeof fetch;
    await expect(createOpenAiProvider({ apiKey: "K", model: "M", fetch: hang }).complete({ ...req, timeoutMs: 20 })).rejects.toThrow(/timed out after 20 ms/);
  });

  it("factory demands key and model except for mock/none", () => {
    expect(createProviderFromEnv({ AI_PROVIDER: "mock" })?.name).toBe("mock");
    expect(createProviderFromEnv({})).toBeNull();
    expect(() => createProviderFromEnv({ AI_PROVIDER: "anthropic" })).toThrow(ConfigError);
    expect(() => createProviderFromEnv({ AI_PROVIDER: "openai", OPENAI_API_KEY: "k" })).toThrow(/OPENAI_MODEL/);
    expect(() => createProviderFromEnv({ AI_PROVIDER: "x" })).toThrow(/not one of/);
  });
});

const session = (id: string, kg: number): Session => ({
  id,
  kind: "gym",
  type: "Gym",
  focus: "Push",
  startedAt: 0,
  endedAt: 1_000,
  exercises: [{ name: "Bench press", sets: [{ reps: 5, kg, max: false }] }],
  source: "app",
});

describe("runJob pipeline", () => {
  const input = buildPlanInput([session("a", 60)], [], [], "Gym", "Push");
  const scripted = (...replies: (string | Error)[]): AiProvider & { n: number } => {
    const p = {
      name: "scripted",
      supportsImages: false,
      n: 0,
      async complete() {
        const r = replies[Math.min(p.n++, replies.length - 1)]!;
        if (r instanceof Error) throw r;
        return r;
      },
    };
    return p;
  };

  it("no provider: code fallback", async () => {
    const r = await runJob(planSessionJob, input, null, silentLogger);
    expect(r.path).toBe("fallback");
    expect(r.value).toEqual(input.rules);
  });

  it("mock provider: AI path", async () => {
    const r = await runJob(planSessionJob, input, new MockProvider(), silentLogger);
    expect(r.path).toBe("ai");
    expect(r.value.rationale).toContain("Mock");
  });

  it("invalid first answer, valid second: retried once, AI path", async () => {
    const p = scripted("nope", '```json\n{"rationale":"ok","exercises":[]}\n```');
    const r = await runJob(planSessionJob, input, p, silentLogger);
    expect(r).toMatchObject({ path: "ai", value: { rationale: "ok" } });
    expect(p.n).toBe(2);
  });

  it("two invalid answers: fallback after exactly two calls", async () => {
    const p = scripted("nope");
    const r = await runJob(planSessionJob, input, p, silentLogger);
    expect(r.path).toBe("fallback");
    expect(p.n).toBe(2);
  });
});

describe("plan safety limits", () => {
  it("caps weight at 1.25x the heaviest logged; cuts exercises and sets", () => {
    const draft = {
      rationale: "x",
      exercises: Array.from({ length: 15 }, (_, i) => ({ name: i === 0 ? "Bench press" : `Ex ${i}`, sets: Array.from({ length: 12 }, () => ({ reps: 5, kg: 200, max: false })) })),
    };
    const out = applyPlanLimits(draft, [session("a", 60)]);
    expect(out.exercises).toHaveLength(MAX_PLAN_EXERCISES);
    expect(out.exercises[0]!.sets).toHaveLength(MAX_PLAN_SETS);
    expect(out.exercises[0]!.sets[0]!.kg).toBe(75);
    expect(out.exercises[1]!.sets[0]!.kg).toBe(200);
  });
});
