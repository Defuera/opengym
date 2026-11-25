import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../functions/_generated/api";
import { createOpenAiProvider } from "../functions/model/ai/providers/openai";
import { MOCK_TRANSCRIPT } from "../functions/model/ai/providers/mock";
import { listError } from "../functions/jobs/models";
import { TOKEN, setup, settle, type T } from "./helpers";

let t: T;
beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(Date.UTC(2026, 0, 15, 12));
  t = setup();
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

const create = (threadId = "th1") => t.mutation(api.commands.threads.create, { token: TOKEN, threadId });
async function upload(fileId: string, name = "voice.m4a", mime = "audio/mp4", content: string | Uint8Array = "AUDIO") {
  const storageId = await t.run((c) => c.storage.store(new Blob([content as BlobPart], { type: mime })));
  return t.mutation(api.commands.files.register, { token: TOKEN, fileId, storageId, name, mime, size: content.length });
}
const sendVoice = (messageId: string, fileId = "f1", threadId = "th1") => t.mutation(api.commands.messages.sendVoice, { token: TOKEN, threadId, messageId, fileId });
const sendVoiceWith = (messageId: string, context: object) => t.mutation(api.commands.messages.sendVoice, { token: TOKEN, threadId: "th1", messageId, fileId: "f1", context });
const retry = (messageId: string) => t.mutation(api.commands.messages.retryVoice, { token: TOKEN, messageId });
const messages = (threadId = "th1") => t.query(api.queries.messages.list, { token: TOKEN, threadId });
const thread = async () => (await t.query(api.queries.threads.list, { token: TOKEN }))[0]!;

describe("sendVoice", () => {
  it("gives an audio file the kind audio", async () => {
    expect(await upload("f1")).toMatchObject({ kind: "audio", mime: "audio/mp4" });
  });

  it("stores a pending message, counts one pending reply, and is idempotent", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await create();
    await upload("f1");
    expect(await sendVoice("v1")).toBe("v1");
    expect(await sendVoice("v1")).toBe("v1");
    expect(await messages()).toMatchObject([{ messageId: "v1", role: "user", text: "", fileIds: ["f1"], voice: "pending" }]);
    expect(await thread()).toMatchObject({ status: "thinking", pending: 1 });
  });

  it("validates the thread, the file and the id", async () => {
    await create();
    await upload("f1");
    await upload("t1", "a.txt", "text/plain", "x");
    await expect(sendVoice("v1", "f1", "nope")).rejects.toThrow(/thread not found/);
    await expect(sendVoice("v1", "nope")).rejects.toThrow(/file not found/);
    await expect(sendVoice("v1", "t1")).rejects.toThrow(/not audio/);
    await expect(sendVoice("")).rejects.toThrow(/messageId/);
    expect(await messages()).toHaveLength(0);
    expect(await thread()).toMatchObject({ status: "idle", pending: 0 });
  });
});

describe("a voice message carries the screen context of a typed one", () => {
  it("stores the context, and the coach turn reads the screen from it", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await create();
    await upload("f1");
    await sendVoiceWith("v1", { screen: "log" });
    await settle(t);
    const stored = await t.run((c) => c.db.query("messages").withIndex("by_messageId", (q) => q.eq("messageId", "v1")).unique());
    expect(stored).toMatchObject({ voice: "done", context: { screen: "log" } });
    const input = await t.query(internal.jobs.coachTurn.input, { threadId: "th1", messageId: "v1" });
    expect(input!.turn.screen).toBe("log");
  });

  it("refuses a context id that is too long, like a typed message", async () => {
    await create();
    await upload("f1");
    await expect(sendVoiceWith("v1", { screen: "chat", entryId: "" })).rejects.toThrow(/context\.entryId/);
  });

  it("a voice message without context is still answered as a plain chat", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await create();
    await upload("f1");
    await sendVoice("v1");
    await settle(t);
    expect((await t.query(internal.jobs.coachTurn.input, { threadId: "th1", messageId: "v1" }))!.turn.screen).toBe("chat");
  });
});

describe("transcribe", () => {
  it("stores the transcript, runs the coach once, and the counters end as for a typed message", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await create();
    await upload("f1");
    await sendVoice("v1");
    await settle(t);
    const ms = await messages();
    expect(ms.map((m) => m.role)).toEqual(["user", "assistant"]);
    expect(ms[0]).toMatchObject({ text: MOCK_TRANSCRIPT, voice: "done" });
    expect(ms[1]!.text).toMatch(/^Mock coach/);
    expect(ms[1]!.sources.some((s) => s.startsWith("file:"))).toBe(false);
    expect(await thread()).toMatchObject({ status: "idle", pending: 0, title: "Mock voice: my left knee felt tight on" });
  });

  it("an empty transcript fails the message, frees the thread and gives no reply", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await create();
    await upload("f1", "silence.m4a");
    await sendVoice("v1");
    await settle(t);
    expect(await messages()).toMatchObject([{ voice: "failed", text: "" }]);
    expect(await thread()).toMatchObject({ status: "idle", pending: 0 });
  });

  it("a provider failure fails the message and logs no raw provider text", async () => {
    vi.stubEnv("AI_PROVIDER", "openai");
    vi.stubEnv("OPENAI_API_KEY", "sk-secret-123");
    vi.stubEnv("OPENAI_MODEL", "m");
    vi.stubGlobal("fetch", async () => new Response("Incorrect API key provided: sk-secret-123", { status: 401 }));
    const logs: string[] = [];
    vi.spyOn(console, "error").mockImplementation((...a) => void logs.push(a.join(" ")));
    await create();
    await upload("f1");
    await sendVoice("v1");
    await settle(t);
    expect(await messages()).toMatchObject([{ voice: "failed" }]);
    expect(await thread()).toMatchObject({ status: "idle", pending: 0 });
    expect(logs.join("\n")).toContain("HTTP 401");
    expect(logs.join("\n")).not.toContain("sk-secret");
  });

  it("a provider without transcribe fails the message", async () => {
    vi.stubEnv("AI_PROVIDER", "anthropic");
    vi.stubEnv("ANTHROPIC_API_KEY", "k");
    vi.stubEnv("ANTHROPIC_MODEL", "m");
    vi.stubGlobal("fetch", async () => { throw new Error("must not be called"); });
    await create();
    await upload("f1");
    await sendVoice("v1");
    await settle(t);
    expect(await messages()).toMatchObject([{ voice: "failed" }]);
    expect(await thread()).toMatchObject({ status: "idle", pending: 0 });
  });

  it("no reply before the transcript: a pending voice message is not a coach trigger", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await create();
    await upload("f1");
    await sendVoice("v1");
    await t.mutation(api.commands.messages.send, { token: TOKEN, threadId: "th1", messageId: "v1", text: "x" }); // resend of the id
    expect(await t.query(api.queries.threads.list, { token: TOKEN })).toMatchObject([{ pending: 1 }]);
  });
});

describe("retryVoice", () => {
  it("only for a failed voice message; then the transcript and the reply arrive", async () => {
    vi.stubEnv("AI_PROVIDER", "none");
    await create();
    await upload("f1");
    await sendVoice("v1");
    expect(await retry("v1")).toBe(false); // pending
    expect(await retry("nope")).toBe(false);
    await settle(t);
    expect(await messages()).toMatchObject([{ voice: "failed" }]);
    vi.stubEnv("AI_PROVIDER", "mock");
    expect(await retry("v1")).toBe(true);
    expect(await messages()).toMatchObject([{ voice: "pending" }]);
    expect(await thread()).toMatchObject({ status: "thinking", pending: 1 });
    await settle(t);
    expect((await messages()).map((m) => m.role)).toEqual(["user", "assistant"]);
    expect(await retry("v1")).toBe(false); // done
    expect(await thread()).toMatchObject({ status: "idle", pending: 0 });
  });
});

describe("audio and the coach", () => {
  it("the audio file is not in the model input: no image, no file note, only the transcript", async () => {
    vi.stubEnv("AI_PROVIDER", "openai");
    vi.stubEnv("OPENAI_API_KEY", "k");
    vi.stubEnv("OPENAI_MODEL", "m");
    const chatBodies: string[] = [];
    vi.stubGlobal("fetch", async (url: string, init: RequestInit) => {
      if (url.endsWith("/v1/audio/transcriptions")) return new Response(JSON.stringify({ text: "  my knee hurts  " }), { status: 200 });
      const body = init.body as string;
      chatBodies.push(body);
      const system: string = JSON.parse(body).messages[0].content;
      const job = system.match(/^JOB: (\w+)/m)?.[1];
      const reply = job === "coach_turn" ? '{"message":"Rest it."}' : '{"summary":"s"}';
      return new Response(JSON.stringify({ choices: [{ message: { content: reply } }] }), { status: 200 });
    });
    await create();
    await upload("f1", "secret-recording.m4a");
    await sendVoice("v1");
    await settle(t);
    const ms = await messages();
    expect(ms[0]).toMatchObject({ text: "my knee hurts", voice: "done" });
    expect(ms[1]).toMatchObject({ text: "Rest it.", sources: [] });
    const chat = chatBodies.find((b) => b.includes("JOB: coach_turn"))!;
    expect(chat).toContain("my knee hurts");
    expect(chat).not.toContain("secret-recording");
    expect(chat).not.toContain("image_url");
  });
});

describe("openai transcription request", () => {
  it("posts multipart with model and file to /audio/transcriptions", async () => {
    const calls: { url: string; init: RequestInit }[] = [];
    const f = (async (url: string, init: RequestInit) => {
      calls.push({ url, init });
      return new Response(JSON.stringify({ text: "hello" }), { status: 200 });
    }) as unknown as typeof fetch;
    const p = createOpenAiProvider({ apiKey: "K", model: "M", fetch: f, baseUrl: "http://local:1", transcribeModel: "tm" });
    expect(await p.transcribe!(new Uint8Array([1, 2, 3]), "audio/mp4", "voice.m4a")).toBe("hello");
    const c = calls[0]!;
    expect(c.url).toBe("http://local:1/v1/audio/transcriptions");
    expect(c.init.headers).toEqual({ authorization: "Bearer K" }); // no JSON content-type: fetch sets the boundary
    const form = c.init.body as FormData;
    expect(form.get("model")).toBe("tm");
    const file = form.get("file") as File;
    expect(file.name).toBe("voice.m4a");
    expect(file.type).toBe("audio/mp4");
    expect(file.size).toBe(3);
    expect(c.init.signal).toBeDefined();
  });

  it("uses gpt-4o-transcribe by default and reduces an error to a short text", async () => {
    let model: unknown;
    const ok = (async (_u: string, init: RequestInit) => ((model = (init.body as FormData).get("model")), new Response('{"text":"x"}', { status: 200 }))) as unknown as typeof fetch;
    await createOpenAiProvider({ apiKey: "K", model: "M", fetch: ok }).transcribe!(new Uint8Array([1]), "audio/mp4", "a.m4a");
    expect(model).toBe("gpt-4o-transcribe");
    const bad = (async () => new Response("echo sk-abc", { status: 401 })) as unknown as typeof fetch;
    const err = await createOpenAiProvider({ apiKey: "K", model: "M", fetch: bad }).transcribe!(new Uint8Array([1]), "audio/mp4", "a.m4a").catch((e) => e);
    expect(listError(err)).toBe("The provider answered HTTP 401.");
  });
});

describe("commands/voice:transcribe (the text for the text field)", () => {
  const ask = (fileId = "f1", token = TOKEN) => t.action(api.commands.voice.transcribe, { token, fileId });
  const fileRows = () => t.run((c) => c.db.query("files").collect());
  const blobs = () => t.run((c) => c.db.system.query("_storage").collect());

  it("returns the text, stores no message, and removes the audio file and blob", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await create();
    await upload("f1");
    expect(await ask()).toEqual({ ok: true, text: MOCK_TRANSCRIPT });
    expect(await messages()).toHaveLength(0);
    expect(await thread()).toMatchObject({ status: "idle", pending: 0 });
    expect(await fileRows()).toHaveLength(0);
    expect(await blobs()).toHaveLength(0);
  });

  it("trims and caps the text like a typed message", async () => {
    vi.stubEnv("AI_PROVIDER", "openai");
    vi.stubEnv("OPENAI_API_KEY", "k");
    vi.stubEnv("OPENAI_MODEL", "m");
    vi.stubGlobal("fetch", async () => new Response(JSON.stringify({ text: `  ${"a".repeat(9000)}  ` }), { status: 200 }));
    await upload("f1");
    const out = await ask();
    expect(out.ok && out.text.length).toBe(8000);
  });

  it("an empty transcript is a short reason and the file stays for a retry", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await upload("f1", "silence.m4a");
    expect(await ask()).toEqual({ ok: false, reason: "No speech was heard." });
    expect(await fileRows()).toHaveLength(1);
  });

  it("a missing file or a file that is not audio", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await upload("t1", "a.txt", "text/plain", "x");
    expect(await ask("nope")).toEqual({ ok: false, reason: "The recording is gone." });
    expect(await ask("t1")).toEqual({ ok: false, reason: "The recording is gone." });
    expect(await fileRows()).toHaveLength(1);
  });

  it("a wrong or empty token is refused and nothing is read or removed", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await upload("f1");
    await expect(ask("f1", "wrong")).rejects.toThrow(/unauthorized/);
    await expect(ask("f1", "")).rejects.toThrow(/unauthorized/);
    expect(await fileRows()).toHaveLength(1);
  });

  it("a provider failure gives a reduced reason with no provider text, and keeps the file", async () => {
    vi.stubEnv("AI_PROVIDER", "openai");
    vi.stubEnv("OPENAI_API_KEY", "sk-secret-123");
    vi.stubEnv("OPENAI_MODEL", "m");
    vi.stubGlobal("fetch", async () => new Response("Incorrect API key provided: sk-secret-123", { status: 401 }));
    vi.spyOn(console, "error").mockImplementation(() => {});
    await upload("f1");
    const out = await ask();
    expect(out).toEqual({ ok: false, reason: "The provider answered HTTP 401." });
    expect(JSON.stringify(out)).not.toContain("sk-secret");
    expect(await fileRows()).toHaveLength(1);
  });

  it("a provider without transcribe says so", async () => {
    vi.stubEnv("AI_PROVIDER", "none");
    await upload("f1");
    expect(await ask()).toEqual({ ok: false, reason: "The AI provider cannot transcribe." });
  });
});
