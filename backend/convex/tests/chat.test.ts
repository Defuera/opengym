import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../functions/_generated/api";
import { COACH_TURN_FALLBACK } from "../functions/model/ai/jobs/coachTurn";
import { CHAT_HISTORY_MESSAGES } from "../functions/model/chatInput";
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

const TEXT = "I want to bench press 80 kg by spring, and my left wrist dislikes straight bars";
const create = (threadId = "th1", title: string | null = "Bench") => t.mutation(api.commands.threads.create, { token: TOKEN, threadId, title: title ?? undefined });
const send = (messageId: string, text = TEXT, threadId = "th1", fileIds?: string[]) => t.mutation(api.commands.messages.send, { token: TOKEN, threadId, messageId, text, fileIds });
const threads = () => t.query(api.queries.threads.list, { token: TOKEN });
const messages = (threadId = "th1") => t.query(api.queries.messages.list, { token: TOKEN, threadId });

describe("chat round trip (mock provider)", () => {
  it("stores the user message at once, then the answer and the summary arrive", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await create();
    expect((await threads())[0]).toMatchObject({ threadId: "th1", status: "idle", summary: "" });

    await send("m1");
    // Before the job runs: the user message is there, the thread shows progress.
    expect(await messages()).toMatchObject([{ messageId: "m1", role: "user", text: TEXT }]);
    expect((await threads())[0]).toMatchObject({ status: "thinking" });

    await settle(t);
    const ms = await messages();
    expect(ms.map((m) => m.role)).toEqual(["user", "assistant"]);
    expect(ms[1]!.text).toMatch(/^Mock coach/);
    expect(ms[1]!.sources).toEqual([]); // no log, goals or context existed yet when the coach read
    const th = (await threads())[0]!;
    expect(th).toMatchObject({ status: "idle", pending: 0, lastMessage: ms[1]!.text });
    expect(th.error).toBeUndefined();
    expect(th.summary).toMatch(/^Mock summary: I want to bench/);

    // Nothing is written silently from a chat (ADR-032): no goal, no note, no session.
    expect(await t.query(api.queries.goals.list, { token: TOKEN })).toHaveLength(0);
    expect(await t.query(api.queries.context.list, { token: TOKEN })).toHaveLength(0);
    expect(await t.run((c) => c.db.query("sessions").collect())).toHaveLength(0);
  });

  it("the second thread reads the goal, the notes and the other thread's summary", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await create();
    await t.mutation(api.commands.goals.create, { token: TOKEN, goalId: "g1", title: "Bench press 80 kg", kind: "strength", exercise: "Bench press", targetKg: 80 });
    await t.mutation(api.commands.context.create, { token: TOKEN, itemId: "c1", text: "Left wrist dislikes straight bars", topic: "wrist" });
    await send("m1");
    await settle(t);
    await create("th2", "Other");
    await send("m2", TEXT, "th2");
    await settle(t);
    const ms = await messages("th2");
    expect(ms[1]!.sources).toEqual(expect.arrayContaining(["Bench thread", "goals", "context notes"]));
    expect(await t.query(api.queries.goals.list, { token: TOKEN })).toHaveLength(1);
    expect(await t.query(api.queries.context.list, { token: TOKEN })).toHaveLength(1);
  });

  it("send is idempotent per messageId and needs an existing thread", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await create();
    await create(); // resend is harmless
    await send("m1");
    await send("m1");
    await settle(t);
    expect(await messages()).toHaveLength(2);
    await expect(send("m9", TEXT, "nope")).rejects.toThrow(/thread not found/);
    await expect(send("m8", "")).rejects.toThrow(/message/);
    await expect(t.mutation(api.commands.threads.create, { token: TOKEN, threadId: "x", title: "" })).rejects.toThrow(/thread/);
  });

  it("a resend on an idle thread writes nothing and schedules nothing", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await create();
    await send("m1");
    await settle(t);
    const before = await t.run(async (c) => ({ messages: await c.db.query("messages").collect(), threads: await c.db.query("threads").collect() }));
    const jobsBefore = await t.run((c) => c.db.system.query("_scheduled_functions").collect());
    await send("m1");
    const after = await t.run(async (c) => ({ messages: await c.db.query("messages").collect(), threads: await c.db.query("threads").collect() }));
    expect(after).toEqual(before);
    expect(await t.run((c) => c.db.system.query("_scheduled_functions").collect())).toHaveLength(jobsBefore.length);
  });

  it("after a failed reply a resend of the same id gives one user and one assistant message, and idle", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await create();
    await send("m1");
    // The first reply fails: cancel its job and record the failure.
    await t.run(async (c) => {
      for (const j of await c.db.system.query("_scheduled_functions").collect()) await c.scheduler.cancel(j._id);
    });
    await t.mutation(internal.jobs.chat.fail, { userId: "owner", threadId: "th1", error: "boom" });
    expect((await threads())[0]).toMatchObject({ status: "failed", pending: 0 });

    await send("m1");
    expect((await threads())[0]).toMatchObject({ status: "thinking", pending: 1 });
    await send("m1"); // a second resend while thinking changes nothing
    expect((await threads())[0]).toMatchObject({ pending: 1 });
    await settle(t);
    expect((await messages()).map((m) => m.role)).toEqual(["user", "assistant"]);
    expect((await threads())[0]).toMatchObject({ status: "idle", pending: 0 });
    expect((await threads())[0]!.error).toBeUndefined();
  });

  it("a resend of an already answered message does not get a second answer, even if a later reply failed", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await create();
    await send("m1");
    await settle(t);
    await send("m2", "again");
    await t.run(async (c) => {
      for (const j of await c.db.system.query("_scheduled_functions").collect()) if (j.state.kind === "pending") await c.scheduler.cancel(j._id);
    });
    await t.mutation(internal.jobs.chat.fail, { userId: "owner", threadId: "th1", error: "boom" });
    await send("m1"); // answered: no new reply
    expect((await threads())[0]).toMatchObject({ status: "failed", pending: 0 });
    await send("m2"); // not answered: retried
    await settle(t);
    expect((await messages()).map((m) => m.role)).toEqual(["user", "assistant", "user", "assistant"]);
    expect((await threads())[0]).toMatchObject({ status: "idle", pending: 0 });
  });

  it("two quick messages: status stays thinking until both answers are stored", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await create();
    await send("m1", "hello");
    await send("m2", "again");
    expect((await threads())[0]).toMatchObject({ status: "thinking", pending: 2 });
    await settle(t);
    expect((await messages()).map((m) => m.role).sort()).toEqual(["assistant", "assistant", "user", "user"]);
    expect((await threads())[0]).toMatchObject({ status: "idle", pending: 0 });
  });

  it("remove deletes the thread and its messages", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await create();
    await send("m1");
    await settle(t);
    expect(await t.mutation(api.commands.threads.remove, { token: TOKEN, threadId: "th1" })).toBe(true);
    expect(await t.run((c) => c.db.query("messages").collect())).toHaveLength(0);
    expect(await threads()).toHaveLength(0);
    expect(await t.mutation(api.commands.threads.remove, { token: TOKEN, threadId: "th1" })).toBe(false);
  });

  it("a thread deleted while the job runs leaves no stray rows", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await create();
    await send("m1");
    await t.mutation(api.commands.threads.remove, { token: TOKEN, threadId: "th1" });
    await settle(t);
    expect(await t.run((c) => c.db.query("messages").collect())).toHaveLength(0);
    expect(await t.query(api.queries.goals.list, { token: TOKEN })).toHaveLength(0);
  });

  it("threads list newest first (by last activity)", async () => {
    await create("a", "A");
    vi.setSystemTime(Date.UTC(2026, 0, 15, 13));
    await create("b", "B");
    expect((await threads()).map((x) => x.threadId)).toEqual(["b", "a"]);
    vi.setSystemTime(Date.UTC(2026, 0, 15, 14));
    await send("m1", "hi", "a");
    expect((await threads()).map((x) => x.threadId)).toEqual(["a", "b"]);
    await settle(t);
  });
});

describe("thread titles", () => {
  const rename = (title: string, threadId = "th1") => t.mutation(api.commands.threads.rename, { token: TOKEN, threadId, title });
  const row = async (threadId = "th1") => (await threads()).find((x) => x.threadId === threadId)!;

  it("create needs no title: New chat, set by auto; a given title counts as the user's", async () => {
    await create("a", null);
    await create("b", "Mine");
    expect(await row("a")).toMatchObject({ title: "New chat", titleSource: "auto" });
    expect(await row("b")).toMatchObject({ title: "Mine", titleSource: "user" });
  });

  it("the first message sets a plain-code title at once (word boundary, max 40, capital)", async () => {
    await create("th1", null);
    await send("m1", "i want to bench press 80 kg by spring, and my left wrist dislikes straight bars");
    const title = (await row()).title;
    expect(title).toBe("I want to bench press 80 kg by spring");
    expect(title.length).toBeLessThanOrEqual(40);
    await settle(t); // provider none: the code title stays
    expect(await row()).toMatchObject({ title, titleSource: "auto" });
    await send("m2", "something else entirely");
    expect((await row()).title).toBe(title); // only the first message names the thread
    await settle(t);
  });

  it("with the mock provider the code title stays: the coach turn runs no title job", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await create("th1", null);
    await send("m1", TEXT);
    const code = (await row()).title;
    await settle(t);
    expect(await row()).toMatchObject({ title: code, titleSource: "auto" });
  });

  it("a rename wins and stays", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await create("th1", null);
    await send("m1", TEXT);
    expect(await rename("  My bench plan ")).toBe(true);
    expect(await row()).toMatchObject({ title: "My bench plan", titleSource: "user" });
    await settle(t); // the job finishes after the rename
    expect(await row()).toMatchObject({ title: "My bench plan", titleSource: "user" });
    await send("m2", "more");
    await settle(t);
    expect((await row()).title).toBe("My bench plan");
  });

  it("rename checks the title and the thread", async () => {
    await create();
    await expect(rename("   ")).rejects.toThrow(/thread/);
    await expect(rename("x".repeat(61))).rejects.toThrow(/thread/);
    expect(await rename("ok", "nope")).toBe(false);
  });

  it("an old row without titleSource counts as user: never changed", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await t.run((c) => c.db.insert("threads", { userId: "owner", threadId: "old", title: "Old name", createdAt: 1, updatedAt: 1, summary: "", status: "idle", pending: 0 }));
    await send("m1", TEXT, "old");
    expect((await row("old")).title).toBe("Old name");
    await settle(t);
    expect((await row("old")).title).toBe("Old name");
    expect(await rename("New", "old")).toBe(true);
    expect(await row("old")).toMatchObject({ title: "New", titleSource: "user" });
  });
});

describe("chat without AI (AI_PROVIDER=none)", () => {
  it("stores the message, answers with the fixed reply, summary is the last user message", async () => {
    await create();
    await send("m1");
    await settle(t);
    const ms = await messages();
    expect(ms).toMatchObject([{ role: "user", text: TEXT }, { role: "assistant", text: COACH_TURN_FALLBACK, sources: [] }]);
    expect((await threads())[0]).toMatchObject({ status: "idle", summary: TEXT.slice(0, 400) });
    expect(await t.query(api.queries.goals.list, { token: TOKEN })).toHaveLength(0);
    expect(await t.query(api.queries.context.list, { token: TOKEN })).toHaveLength(0);
  });
});

describe("chat limits and failure", () => {
  it("the model gets at most the last 20 messages, ending with the new one", async () => {
    await create();
    const base = Date.now();
    for (let i = 0; i < 30; i++) {
      await t.run((c) => c.db.insert("messages", { userId: "owner", messageId: `h${i}`, threadId: "th1", role: i % 2 ? "assistant" : "user", text: `msg ${i}`, fileIds: [], sources: [], createdAt: base + i }));
    }
    await t.run((c) => c.db.insert("messages", { userId: "owner", messageId: "last", threadId: "th1", role: "user", text: "newest", fileIds: [], sources: [], createdAt: base + 99 }));
    const inp = await t.query(internal.jobs.coachTurn.input, { userId: "owner", threadId: "th1", messageId: "last" });
    expect(inp!.chat.history).toHaveLength(CHAT_HISTORY_MESSAGES);
    expect(inp!.chat.history.at(-1)).toEqual({ role: "user", content: "newest" });
    expect(inp!.chat.history[0]!.content).toBe("msg 11");
    expect(await t.query(internal.jobs.coachTurn.input, { userId: "owner", threadId: "th1", messageId: "ghost" })).toBeNull();
  });

  it("an image attachment goes to the model when the provider takes images, and the file is a source", async () => {
    const bodies: any[] = []; // eslint-disable-line @typescript-eslint/no-explicit-any
    vi.stubEnv("AI_PROVIDER", "openai");
    vi.stubEnv("OPENAI_API_KEY", "k");
    vi.stubEnv("OPENAI_MODEL", "m");
    vi.stubGlobal("fetch", async (_u: string, init: RequestInit) => {
      const b = JSON.parse(init.body as string);
      bodies.push(b);
      const job = b.messages[0].content.match(/^JOB: (\w+)/m)?.[1];
      const content = job === "coach_turn" ? '{"message":"Looks good."}' : job === "summarise_thread" ? '{"summary":"s"}' : '{"goals":[],"context":[]}';
      return new Response(JSON.stringify({ choices: [{ message: { content } }] }), { status: 200 });
    });
    await create();
    const storageId = await t.run((c) => c.storage.store(new Blob([new Uint8Array([1, 2, 3])], { type: "image/png" })));
    await t.mutation(api.commands.files.register, { token: TOKEN, fileId: "img1", storageId, name: "machine.png", mime: "image/png", size: 3 });
    await send("m1", "what do you see", "th1", ["img1"]);
    await settle(t);
    const chat = bodies.find((b) => b.messages[0].content.includes("JOB: coach_turn"));
    const last = chat.messages.at(-1);
    expect(JSON.stringify(last.content)).toContain("data:image/png;base64,AQID");
    expect((await messages())[1]).toMatchObject({ text: "Looks good.", sources: ["file: machine.png"] });
  });

  it("a failing reply shows a short error on the thread and keeps the user message", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await create();
    await send("m1");
    // The file store breaks for this attachment: point the message at a file whose blob is gone.
    const storageId = await t.run((c) => c.storage.store(new Blob(["x"], { type: "text/plain" })));
    await t.mutation(api.commands.files.register, { token: TOKEN, fileId: "f1", storageId, name: "a.txt", mime: "text/plain", size: 1 });
    await t.run(async (c) => {
      const m = await c.db.query("messages").first();
      await c.db.patch(m!._id, { fileIds: ["f1"] });
      await c.storage.delete(storageId);
    });
    // Missing blob is skipped, not fatal: the answer still arrives.
    await settle(t);
    expect((await threads())[0]).toMatchObject({ status: "idle" });

    // A real failure: the fail mutation records it.
    await send("m2", "again");
    await t.mutation(internal.jobs.chat.fail, { userId: "owner", threadId: "th1", error: "boom" });
    expect((await threads())[0]).toMatchObject({ status: "failed", error: "boom", pending: 0 });
    await settle(t);
    expect((await messages()).filter((m) => m.role === "user")).toHaveLength(2);
  });
});

describe("access", () => {
  it("every chat function rejects a wrong token", async () => {
    const bad = "nope";
    await expect(t.mutation(api.commands.threads.create, { token: bad, threadId: "a", title: "A" })).rejects.toThrow(/unauthorized/);
    await expect(t.mutation(api.commands.threads.rename, { token: bad, threadId: "a", title: "A" })).rejects.toThrow(/unauthorized/);
    await expect(t.mutation(api.commands.threads.remove, { token: bad, threadId: "a" })).rejects.toThrow(/unauthorized/);
    await expect(t.mutation(api.commands.messages.send, { token: bad, threadId: "a", messageId: "m", text: "x" })).rejects.toThrow(/unauthorized/);
    await expect(t.query(api.queries.threads.list, { token: bad })).rejects.toThrow(/unauthorized/);
    await expect(t.query(api.queries.messages.list, { token: bad, threadId: "a" })).rejects.toThrow(/unauthorized/);
  });
});

