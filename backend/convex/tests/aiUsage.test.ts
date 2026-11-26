import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../functions/_generated/api";
import { AI_CALL_KEEP_MS } from "../functions/lib/constants";
import { MOCK_CHAT_USAGE, MOCK_IMAGE_SPEC, MOCK_TRANSCRIBE_USAGE } from "../functions/model/ai/providers/mock";
import { TOKEN, setup, settle, type T } from "./helpers";

const NOW = Date.UTC(2026, 10, 26, 12);
let t: T;
beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
  t = setup();
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

const usageRows = () => t.run((c) => c.db.query("aiUsage").collect());
const calls = () => t.run((c) => c.db.query("aiCalls").collect());
/** Runs the summarise_thread job through its real action, so the provider is called from an action as in production. */
async function run(): Promise<void> {
  await t.mutation(api.commands.threads.create, { token: TOKEN, threadId: "th1" });
  await t.action(internal.jobs.chat.summarise, { userId: "owner", threadId: "th1" });
}
const pathOfLastCall = async () => (await calls()).at(-1)!.path;

/** Stubs the OpenAI chat endpoint: each call takes the next reply and reports the given usage. */
function stubChat(replies: string[]) {
  vi.stubEnv("AI_PROVIDER", "openai");
  vi.stubEnv("OPENAI_API_KEY", "test-key");
  vi.stubEnv("OPENAI_MODEL", "test-model");
  vi.stubGlobal("fetch", async () => new Response(JSON.stringify({ choices: [{ message: { content: replies.shift() ?? "" } }], usage: { prompt_tokens: 50, completion_tokens: 10, prompt_tokens_details: { cached_tokens: 20 } } }), { status: 200 }));
}

describe("aiUsage rows of a job run", () => {
  it("writes one row with the mock numbers, the user id and the ref", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await run();
    expect(await pathOfLastCall()).toBe("ai");
    const rows = await usageRows();
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ ...MOCK_CHAT_USAGE, userId: "owner", job: "summarise_thread", kind: "chat", provider: "mock", model: "mock", ok: true });
    expect(rows[0]!.ms).toBeGreaterThanOrEqual(0);
    expect(rows[0]).not.toHaveProperty("system");
    expect(await calls()).toMatchObject([{ inputTokens: 100, cachedInputTokens: 40, outputTokens: 20, reasoningTokens: 5 }]);
  });

  it("a retry writes two rows and the trace holds the sum", async () => {
    stubChat(["not json", '{"summary":"ok"}']);
    await run();
    expect(await pathOfLastCall()).toBe("ai");
    const rows = await usageRows();
    expect(rows.map((r) => r.ok).sort()).toEqual([false, true]);
    expect(rows.every((r) => r.inputTokens === 50 && r.cachedInputTokens === 20 && r.outputTokens === 10 && r.model === "test-model" && r.provider === "openai")).toBe(true);
    expect(await calls()).toMatchObject([{ inputTokens: 100, cachedInputTokens: 40, outputTokens: 20 }]);
    expect((await calls())[0]!.reasoningTokens).toBeUndefined();
  });

  it("a fallback after two failures writes two failed rows", async () => {
    stubChat(["bad", "worse"]);
    await run();
    expect(await pathOfLastCall()).toBe("fallback");
    const rows = await usageRows();
    expect(rows).toHaveLength(2);
    expect(rows.every((r) => !r.ok)).toBe(true);
  });

  it("a request error is a failed row with no tokens", async () => {
    vi.stubEnv("AI_PROVIDER", "openai");
    vi.stubEnv("OPENAI_API_KEY", "k");
    vi.stubEnv("OPENAI_MODEL", "m");
    vi.stubGlobal("fetch", async () => new Response("boom", { status: 500 }));
    await run();
    const rows = await usageRows();
    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({ ok: false });
    expect(rows[0]!.inputTokens).toBeUndefined();
    expect((await calls())[0]!.inputTokens).toBeUndefined();
  });

  it("no provider: no call, no row", async () => {
    await run();
    expect(await usageRows()).toHaveLength(0);
  });
});

describe("aiUsage ref", () => {
  it("carries the ref of the aiCalls row", async () => {
    await t.mutation(internal.jobs.aiCalls.save, { userId: "owner", job: "coach_turn", provider: "openai", model: "m", system: "S", messages: [], images: 0, attempts: [{ ms: 5, at: NOW, usage: { inputTokens: 3 } }], path: "ai", ms: 5, ref: "msg-1" });
    expect(await usageRows()).toMatchObject([{ ref: "msg-1", inputTokens: 3, at: NOW, userId: "owner", model: "m" }]);
  });
});

describe("aiUsage rows of speech and image calls", () => {
  it("a transcription writes a row with bytes and the mock usage", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    const storageId = await t.run((c) => c.storage.store(new Blob(["AUDIO"], { type: "audio/mp4" })));
    await t.mutation(api.commands.files.register, { token: TOKEN, fileId: "f1", storageId, name: "v.m4a", mime: "audio/mp4", size: 5 });
    expect(await t.action(api.commands.voice.transcribe, { token: TOKEN, fileId: "f1" })).toMatchObject({ ok: true });
    const rows = await usageRows();
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ ...MOCK_TRANSCRIBE_USAGE, userId: "owner", job: "transcribe", kind: "transcribe", model: "mock-transcribe", audioBytes: 5, ok: true, ref: "f1" });
  });

  it("an image call writes a row, and the match job writes a chat row", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await t.mutation(api.commands.exerciseArt.request, { token: TOKEN, names: ["qqqq zzzz"] });
    await settle(t);
    const rows = await usageRows();
    const image = rows.filter((r) => r.kind === "image");
    expect(image).toHaveLength(1);
    expect(image[0]).toMatchObject({ job: "exercise_art", model: "mock-image", images: 1, imageSpec: MOCK_IMAGE_SPEC, inputImages: 0, outputTokens: 1056, userId: "owner", ok: true, ref: "qqqq zzzz" });
    expect(rows.filter((r) => r.kind === "chat").map((r) => r.job)).toEqual(["match_exercise"]);
  });
});

describe("purge", () => {
  it("leaves aiUsage alone when it erases old aiCalls", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await run();
    vi.setSystemTime(NOW + AI_CALL_KEEP_MS + 1000);
    expect((await t.mutation(internal.jobs.purge.run, {})).aiCalls).toBe(1);
    expect(await calls()).toHaveLength(0);
    expect(await usageRows()).toHaveLength(1);
  });
});
