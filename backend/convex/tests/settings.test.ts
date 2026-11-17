import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../functions/_generated/api";
import { TOKEN, setup, settle, type T } from "./helpers";

const ai = (t: T) => t.query(api.queries.settings.ai, { token: TOKEN });
const setModel = (t: T, model: string | null) => t.mutation(api.commands.settings.setAiModel, { token: TOKEN, model });
const rows = (t: T) => t.run((c) => c.db.query("settings").collect());

function useOpenAi() {
  vi.stubEnv("AI_PROVIDER", "openai");
  vi.stubEnv("OPENAI_API_KEY", "sk-secret-key");
  vi.stubEnv("OPENAI_MODEL", "env-model");
}

/** Stub fetch; records url, headers and parsed body of every call. */
function stubFetch(answer: (url: string) => Response) {
  const calls: { url: string; method: string; headers: Record<string, string>; body: any }[] = []; // eslint-disable-line @typescript-eslint/no-explicit-any
  vi.stubGlobal("fetch", async (url: string, init: RequestInit) => {
    calls.push({ url, method: init.method ?? "GET", headers: init.headers as Record<string, string>, body: init.body ? JSON.parse(init.body as string) : undefined });
    return answer(url);
  });
  return calls;
}

describe("coach model setting", () => {
  let t: T;
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(Date.UTC(2026, 10, 17, 20, 50));
    t = setup();
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
  });

  it("needs the token", async () => {
    await expect(t.query(api.queries.settings.ai, { token: "x" })).rejects.toThrow(/unauthorized/);
    await expect(t.mutation(api.commands.settings.setAiModel, { token: "x", model: "m" })).rejects.toThrow(/unauthorized/);
    await expect(t.mutation(api.commands.settings.refreshModels, { token: "x" })).rejects.toThrow(/unauthorized/);
  });

  it("no row: the default comes from the environment, no key in the answer", async () => {
    useOpenAi();
    const r = await ai(t);
    expect(r).toEqual({ provider: "openai", defaultModel: "env-model", model: "env-model", override: null, models: [], fetchedAt: null, error: null });
    expect(JSON.stringify(r)).not.toContain("sk-secret");
    expect(await rows(t)).toHaveLength(0);
  });

  it("AI off: provider none, no model", async () => {
    expect(await ai(t)).toMatchObject({ provider: "none", defaultModel: null, model: null });
  });

  it("set and clear the override; writes are idempotent and use one row", async () => {
    useOpenAi();
    await setModel(t, "gpt-x:1.2");
    await setModel(t, "gpt-x:1.2");
    expect(await ai(t)).toMatchObject({ model: "gpt-x:1.2", override: "gpt-x:1.2", defaultModel: "env-model" });
    await setModel(t, "other");
    expect(await ai(t)).toMatchObject({ model: "other" });
    await setModel(t, null);
    expect(await ai(t)).toMatchObject({ model: "env-model", override: null });
    await setModel(t, null);
    expect(await rows(t)).toHaveLength(1);
  });

  it("validates the id: 1..100 chars of A-Za-z0-9._:-", async () => {
    for (const bad of ["", "has space", "slash/model", "x".repeat(101), "é", "a;b"]) await expect(setModel(t, bad)).rejects.toThrow(/model/);
    await setModel(t, "x".repeat(100));
    await setModel(t, "A-z_0.9:b");
    expect((await ai(t)).override).toBe("A-z_0.9:b");
  });

  it("a model outside the cached list is allowed", async () => {
    useOpenAi();
    stubFetch(() => new Response(JSON.stringify({ data: [{ id: "a" }] }), { status: 200 }));
    await t.mutation(api.commands.settings.refreshModels, { token: TOKEN });
    await settle(t);
    await setModel(t, "not-in-list");
    expect(await ai(t)).toMatchObject({ models: ["a"], override: "not-in-list" });
  });

  it("the effective model reaches the provider request; clearing returns to the env model", async () => {
    useOpenAi();
    const calls = stubFetch(() => new Response(JSON.stringify({ choices: [{ message: { content: JSON.stringify({ modules: [{ type: "trend" }] }) } }] }), { status: 200 }));
    await setModel(t, "my-model");
    await t.action(internal.jobs.dashboards.build, { days: 7, version: 1 });
    expect(calls[0]!.body.model).toBe("my-model");
    await setModel(t, null);
    await t.action(internal.jobs.dashboards.build, { days: 30, version: 2 });
    expect(calls.at(-1)!.body.model).toBe("env-model");
  });

  it("override works when the env has no model (AI on, not off)", async () => {
    vi.stubEnv("AI_PROVIDER", "openai");
    vi.stubEnv("OPENAI_API_KEY", "k");
    vi.stubEnv("OPENAI_MODEL", "");
    const calls = stubFetch(() => new Response(JSON.stringify({ choices: [{ message: { content: JSON.stringify({ modules: [{ type: "trend" }] }) } }] }), { status: 200 }));
    await t.action(internal.jobs.dashboards.build, { days: 7, version: 1 });
    expect(calls).toHaveLength(0); // no model at all: AI off, fallback
    await setModel(t, "chosen");
    await t.action(internal.jobs.dashboards.build, { days: 7, version: 2 });
    expect(calls[0]!.body.model).toBe("chosen");
  });

  it("a model the provider refuses (400/404) falls back to plain code", async () => {
    useOpenAi();
    for (const status of [400, 404]) {
      stubFetch(() => new Response('{"error":{"message":"model not found"}}', { status }));
      await setModel(t, `bad-${status}`);
      await t.action(internal.jobs.dashboards.build, { days: 7, version: status });
      const d = await t.run((c) => c.db.query("dashboards").withIndex("by_days", (q) => q.eq("days", 7)).unique());
      expect(d, String(status)).toMatchObject({ source: "rules" });
    }
  });

  describe("refresh", () => {
    const list = { data: [{ id: "gpt-b" }, { id: "text-embedding-3-small" }, { id: "gpt-a" }, { id: "whisper-1" }, { id: "tts-1" }, { id: "gpt-4o-audio-preview" }, { id: "dall-e-3" }, { id: "gpt-image-1" }, { id: "omni-moderation-latest" }, { id: "gpt-4o-realtime-preview" }, { id: "gpt-a" }] };

    it("stores a filtered, sorted list with the time; uses the existing key", async () => {
      useOpenAi();
      const calls = stubFetch(() => new Response(JSON.stringify(list), { status: 200 }));
      await t.mutation(api.commands.settings.refreshModels, { token: TOKEN });
      await settle(t);
      expect(calls).toHaveLength(1);
      expect(calls[0]).toMatchObject({ url: "https://api.openai.com/v1/models", method: "GET" });
      expect(calls[0]!.headers.authorization).toBe("Bearer sk-secret-key");
      const r = await ai(t);
      expect(r).toMatchObject({ models: ["gpt-a", "gpt-b"], error: null });
      expect(Math.abs(r.fetchedAt! - Date.UTC(2026, 10, 17, 20, 50))).toBeLessThan(1000);
    });

    it("anthropic: GET /v1/models with its headers", async () => {
      vi.stubEnv("AI_PROVIDER", "anthropic");
      vi.stubEnv("ANTHROPIC_API_KEY", "ak");
      vi.stubEnv("ANTHROPIC_MODEL", "claude-x");
      const calls = stubFetch(() => new Response(JSON.stringify({ data: [{ id: "claude-b" }, { id: "claude-a" }] }), { status: 200 }));
      await t.mutation(api.commands.settings.refreshModels, { token: TOKEN });
      await settle(t);
      expect(calls[0]!.url).toMatch(/^https:\/\/api\.anthropic\.com\/v1\/models/);
      expect(calls[0]!.headers).toMatchObject({ "x-api-key": "ak", "anthropic-version": "2023-06-01" });
      expect((await ai(t)).models).toEqual(["claude-a", "claude-b"]);
    });

    it("an error keeps the old list and stores a short text without secrets", async () => {
      useOpenAi();
      stubFetch(() => new Response(JSON.stringify({ data: [{ id: "gpt-a" }] }), { status: 200 }));
      await t.mutation(api.commands.settings.refreshModels, { token: TOKEN });
      await settle(t);
      stubFetch(() => new Response("Incorrect API key provided: sk-secret-key", { status: 401 }));
      vi.setSystemTime(Date.UTC(2026, 10, 18));
      await t.mutation(api.commands.settings.refreshModels, { token: TOKEN });
      await settle(t);
      const r = await ai(t);
      expect(r).toMatchObject({ models: ["gpt-a"], error: "The provider answered HTTP 401." });
      expect(r.fetchedAt!).toBeLessThan(Date.UTC(2026, 10, 18)); // the time of the old list stays
      expect(JSON.stringify(r)).not.toContain("sk-secret");
      stubFetch(() => new Response(JSON.stringify({ data: [{ id: "gpt-z" }] }), { status: 200 }));
      await t.mutation(api.commands.settings.refreshModels, { token: TOKEN });
      await settle(t);
      expect(await ai(t)).toMatchObject({ models: ["gpt-z"], error: null });
    });

    it("a network error is stored as a short text", async () => {
      useOpenAi();
      vi.stubGlobal("fetch", async () => { throw new Error("connect ECONNREFUSED sk-secret-key"); });
      await t.mutation(api.commands.settings.refreshModels, { token: TOKEN });
      await settle(t);
      expect(await ai(t)).toMatchObject({ models: [], error: "Could not reach the provider." });
    });

    it("mock and none: an empty list, no request", async () => {
      const calls = stubFetch(() => new Response("{}", { status: 200 }));
      for (const p of ["mock", "none"]) {
        vi.stubEnv("AI_PROVIDER", p);
        await t.mutation(api.commands.settings.refreshModels, { token: TOKEN });
        await settle(t);
        expect(await ai(t)).toMatchObject({ models: [], error: null });
      }
      expect(calls).toHaveLength(0);
    });
  });
});
