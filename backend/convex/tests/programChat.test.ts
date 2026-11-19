import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../functions/_generated/api";
import { NOT_CONFIGURED_REPLY } from "../functions/model/ai/jobs/chat";
import { MOCK_PROGRAM } from "../functions/model/ai/providers/mock";
import { TOKEN, setup, settle, stubOpenAi, type T } from "./helpers";

/** ADR-026: a program is asked for, discussed and changed in a chat thread that is about the program. */
const NOW = Date.UTC(2026, 10, 19, 12);
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

const create = (threadId: string, extra: Record<string, unknown> = { about: { kind: "program" } }) => t.mutation(api.commands.threads.create, { token: TOKEN, threadId, ...extra } as never);
const send = (messageId: string, text: string, threadId = "th1", fileIds?: string[]) => t.mutation(api.commands.messages.send, { token: TOKEN, threadId, messageId, text, fileIds });
const thread = (threadId = "th1") => t.run((c) => c.db.query("threads").withIndex("by_threadId", (q) => q.eq("threadId", threadId)).unique());
const messages = (threadId = "th1") => t.query(api.queries.messages.list, { token: TOKEN, threadId });
const proposals = () => t.run((c) => c.db.query("proposals").collect());
const forThread = (threadId = "th1") => t.query(api.queries.proposals.forThread, { token: TOKEN, threadId });
const accept = (proposalId: string) => t.mutation(api.commands.proposals.accept, { token: TOKEN, proposalId });
const BRIEF = "Write a two-week knee program.";

/** The stubbed AI: chat_program answers come from `replies` in order (the last one repeats); build_program gives the mock program. */
function stub(replies: string[]) {
  let n = 0;
  return stubOpenAi((job) => {
    if (job === "chat_program") return replies[Math.min(n++, replies.length - 1)]!;
    if (job === "build_program") return JSON.stringify(MOCK_PROGRAM);
    if (job === "summarise_thread") return '{"summary":"s"}';
    return "{}";
  });
}
const propose = (text = "I will write the program now.", brief = BRIEF) => JSON.stringify({ text, proposeProgram: { brief } });
/** A program that exists: asked for through the old request path and agreed, with the mock provider. */
async function existingProgram() {
  vi.stubEnv("AI_PROVIDER", "mock");
  await t.mutation(api.commands.proposals.request, { token: TOKEN, proposalId: "pr0", kind: "program", text: "a program" });
  await settle(t);
  const { programId } = await accept("pr0");
  vi.stubEnv("AI_PROVIDER", "none");
  return programId;
}

describe("commands/threads:create with about", () => {
  it("a new-program thread is titled by code and keeps about as given", async () => {
    await create("th1");
    expect(await thread()).toMatchObject({ title: "New program", titleSource: "auto", about: { kind: "program" } });
    const listed = await t.query(api.queries.threads.list, { token: TOKEN });
    expect(listed[0]!.about).toEqual({ kind: "program" });
  });

  it("with an id the program must exist; the title is the program's; a given title counts as the user's", async () => {
    await expect(create("th1", { about: { kind: "program", id: "nope" } })).rejects.toThrow(/program not found/);
    expect(await thread()).toBeNull();
    await expect(create("th1", { about: { kind: "program", id: "" } })).rejects.toThrow(/about\.id/);
    await expect(create("th1", { about: { kind: "program", id: "x".repeat(101) } })).rejects.toThrow(/about\.id/);
    const programId = await existingProgram();
    await create("th1", { about: { kind: "program", id: programId } });
    expect(await thread()).toMatchObject({ title: MOCK_PROGRAM.title, titleSource: "auto", about: { kind: "program", id: programId } });
    await create("th2", { title: "My own", about: { kind: "program" } });
    expect(await thread("th2")).toMatchObject({ title: "My own", titleSource: "user" });
  });

  it("a resend changes nothing, and an ordinary thread has no about", async () => {
    await create("th1");
    await create("th1", { about: { kind: "program", id: "ignored" } }); // resend: the thread exists, so the program is not looked up
    expect((await thread())!.about).toEqual({ kind: "program" });
    await create("th2", {});
    expect(await thread("th2")).toMatchObject({ title: "New chat" });
    expect((await thread("th2"))!.about).toBeUndefined();
  });
});

describe("the coach reply in a program thread", () => {
  it("stores the message, builds a proposal linked both ways, and runs no title or extract job", async () => {
    const calls = stub([propose()]);
    await create("th1");
    await send("m1", "I want to bench press 80 kg. Please write me a program for my knee.");
    expect((await thread())!.title).toBe("New program"); // not the first words of the message
    await settle(t);
    const ms = await messages();
    expect(ms.map((m) => m.role)).toEqual(["user", "assistant"]);
    expect(ms[1]).toMatchObject({ text: "I will write the program now." });
    const [p] = await proposals();
    expect(p).toMatchObject({ origin: "chat", approval: "explicit", status: "ready", threadId: "th1", messageId: ms[1]!.messageId, target: { kind: "program" } });
    expect(p!.value).toMatchObject({ title: MOCK_PROGRAM.title });
    expect(ms[1]!.proposalId).toBe(p!.proposalId);
    expect(p!.ask.text).toBe(`I want to bench press 80 kg. Please write me a program for my knee.\n\nThe coach's summary of what to write: ${BRIEF}`);
    expect(p!.ask.feedback).toBeUndefined();
    const jobs = calls.map((c) => c.job);
    expect(jobs).toEqual(expect.arrayContaining(["chat_program", "build_program", "summarise_thread"]));
    expect(jobs).not.toContain("title_thread");
    expect(jobs).not.toContain("extract_from_chat");
    expect(await t.query(api.queries.goals.list, { token: TOKEN })).toHaveLength(0);
    expect(await t.query(api.queries.context.list, { token: TOKEN })).toHaveLength(0);
    expect((await thread())).toMatchObject({ status: "idle", pending: 0, summary: "s" });
  });

  it("saveReply with proposeProgram stores a `building` proposal in the same step and schedules the build", async () => {
    stub([propose()]);
    await create("th1");
    await t.mutation(internal.jobs.chat.saveReply, { threadId: "th1", text: "On it.", sources: [], proposeProgram: { brief: BRIEF } });
    const [p] = await proposals();
    expect(p).toMatchObject({ status: "building", threadId: "th1", ask: { text: `The coach's summary of what to write: ${BRIEF}` } });
    expect((await messages())[0]).toMatchObject({ role: "assistant", proposalId: p!.proposalId });
    await settle(t);
    expect((await proposals())[0]!.status).toBe("ready");
    // In an ordinary thread the brief is ignored.
    await create("th2", {});
    await t.mutation(internal.jobs.chat.saveReply, { threadId: "th2", text: "Hi.", sources: [], proposeProgram: { brief: BRIEF } });
    expect(await proposals()).toHaveLength(1);
  });

  it("the request text is cut from the start: the newest text stays, the whole is at most 8000 characters", async () => {
    await create("th1");
    const base = Date.now();
    await t.run(async (c) => {
      await c.db.insert("messages", { messageId: "a", threadId: "th1", role: "user", text: `OLDEST ${"o".repeat(7000)}`, fileIds: [], sources: [], createdAt: base });
      await c.db.insert("messages", { messageId: "b", threadId: "th1", role: "user", text: `${"x".repeat(7000)} NEWEST`, fileIds: [], sources: [], createdAt: base + 1 });
    });
    await t.mutation(internal.jobs.chat.saveReply, { threadId: "th1", text: "On it.", sources: [], proposeProgram: { brief: BRIEF } });
    const text = (await proposals())[0]!.ask.text!;
    expect(text.length).toBeLessThanOrEqual(8000);
    expect(text.endsWith(`NEWEST\n\nThe coach's summary of what to write: ${BRIEF}`)).toBe(true);
    expect(text).not.toContain("OLDEST");
    expect(text).toContain("ooooo"); // the cut is inside the older text
    await settle(t);
  });

  it("a change message declines the first proposal; the new one knows the previous program and the feedback", async () => {
    const calls = stub([propose("First.", "Write a program."), propose("Second.", "Only two days a week.")]);
    await create("th1");
    await send("m1", "write me a program");
    await settle(t);
    await send("m2", "only two days a week");
    await settle(t);
    const ps = (await proposals()).sort((a, b) => a.createdAt - b.createdAt || a._creationTime - b._creationTime);
    expect(ps).toHaveLength(2);
    expect(ps[0]).toMatchObject({ status: "declined" });
    expect(ps[1]).toMatchObject({ status: "ready", ask: { feedback: ["Only two days a week."], previousProposalId: ps[0]!.proposalId } });
    expect(ps[1]!.ask.text).toBe("write me a program\n\nonly two days a week\n\nThe coach's summary of what to write: Only two days a week.");
    const builds = calls.filter((c) => c.job === "build_program");
    expect(builds[1]!.input).toMatchObject({ feedbackFromThePerson: ["Only two days a week."], previousProgram: { title: MOCK_PROGRAM.title } });
    const ms = await messages();
    expect(ms.filter((m) => m.role === "assistant").map((m) => m.proposalId)).toEqual(ps.map((p) => p.proposalId));
  });

  it("a reply without proposeProgram creates nothing", async () => {
    stub([JSON.stringify({ text: "Three sets is fine." })]);
    await create("th1");
    await send("m1", "are three sets enough?");
    await settle(t);
    expect(await proposals()).toHaveLength(0);
    const ms = await messages();
    expect(ms[1]).toMatchObject({ text: "Three sets is fine." });
    expect(ms[1]!.proposalId).toBeUndefined();
  });

  it("invalid JSON twice gives the fallback text and no proposal", async () => {
    const calls = stub(["not json at all"]);
    await create("th1");
    await send("m1", "write a program");
    await settle(t);
    expect(calls.filter((c) => c.job === "chat_program")).toHaveLength(2);
    expect(await proposals()).toHaveLength(0);
    expect((await messages())[1]).toMatchObject({ text: NOT_CONFIGURED_REPLY });
  });

  it("with the AI off the fallback text is stored and no proposal is made", async () => {
    await create("th1");
    await send("m1", "write a program");
    await settle(t);
    expect(await proposals()).toHaveLength(0);
    expect((await messages())[1]).toMatchObject({ text: NOT_CONFIGURED_REPLY });
  });

  it("the mock provider proposes when the last message says \"program\", and a voice message works the same way", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await create("th1");
    await send("m1", "how long should I rest?");
    await settle(t);
    expect(await proposals()).toHaveLength(0);
    await send("m2", "ok, write the program");
    await settle(t);
    expect(await proposals()).toMatchObject([{ status: "ready", origin: "chat" }]);
    // A voice message: the transcript is the text (the mock transcript has no "program" word: a plain answer, no new proposal).
    const storageId = await t.run((c) => c.storage.store(new Blob(["a"], { type: "audio/m4a" })));
    await t.mutation(api.commands.files.register, { token: TOKEN, fileId: "v1", storageId, name: "v.m4a", mime: "audio/m4a", size: 1 });
    await t.mutation(api.commands.messages.sendVoice, { token: TOKEN, threadId: "th1", messageId: "m3", fileId: "v1" });
    await settle(t);
    const ms = await messages();
    expect(ms.at(-1)).toMatchObject({ role: "assistant" });
    expect(ms.find((m) => m.messageId === "m3")).toMatchObject({ voice: "done" });
    expect(await proposals()).toHaveLength(1);
    expect((await thread())!.title).toBe("New program");
  });

  it("in a thread about an existing program the proposal is a change with the program's rev as base, and the coach reads the program", async () => {
    const programId = await existingProgram();
    const calls = stub([propose("Changing it.", "Make it lighter.")]);
    await create("th1", { about: { kind: "program", id: programId } });
    await send("m1", "make the program lighter");
    await settle(t);
    const p = (await proposals()).find((x) => x.threadId === "th1")!;
    expect(p).toMatchObject({ target: { kind: "program", id: programId }, base: 1, status: "ready" });
    expect(calls.find((c) => c.job === "build_program")!.input).toMatchObject({ currentProgram: { title: MOCK_PROGRAM.title } });
  });

  it("an ordinary thread behaves as before: title and extract jobs run, no proposal", async () => {
    const calls = stubOpenAi((job) => (job === "chat" ? "Fine." : job === "summarise_thread" ? '{"summary":"s"}' : job === "title_thread" ? '{"title":"Bench"}' : '{"goals":[],"context":[]}'));
    await create("th1", {});
    await send("m1", "write me a program");
    await settle(t);
    const jobs = calls.map((c) => c.job);
    expect(jobs).toEqual(expect.arrayContaining(["chat", "title_thread", "extract_from_chat", "summarise_thread"]));
    expect(jobs).not.toContain("chat_program");
    expect(await proposals()).toHaveLength(0);
    expect((await messages())[1]!.proposalId).toBeUndefined();
  });
});

describe("accept, forThread, files, remove", () => {
  it("agreeing a new-program proposal makes the thread about the program and titles it, unless the user renamed it", async () => {
    stub([propose()]);
    await create("th1");
    await create("th2");
    await send("m1", "write a program");
    await settle(t);
    const [p] = await proposals();
    const { programId } = await accept(p!.proposalId);
    expect(await thread()).toMatchObject({ about: { kind: "program", id: programId }, title: MOCK_PROGRAM.title, titleSource: "auto" });

    await t.mutation(api.commands.threads.rename, { token: TOKEN, threadId: "th2", title: "Mine" });
    await send("m2", "write a program", "th2");
    await settle(t);
    const p2 = (await proposals()).find((x) => x.threadId === "th2")!;
    await accept(p2.proposalId);
    expect(await thread("th2")).toMatchObject({ about: { kind: "program", id: p2.proposalId }, title: "Mine" });
  });

  it("forThread returns the proposals of the thread, oldest first, in the shape of get, with stale", async () => {
    const programId = await existingProgram();
    stub([propose("One.", "Make it lighter."), propose("Two.", "Make it lighter still.")]);
    await create("th1", { about: { kind: "program", id: programId } });
    await create("th2");
    await send("m1", "lighter program please");
    await settle(t);
    await send("m2", "lighter still, program");
    await settle(t);
    const list = await forThread();
    expect(list).toHaveLength(2);
    expect(list.map((x) => x.status)).toEqual(["declined", "ready"]);
    const get = await t.query(api.queries.proposals.get, { token: TOKEN, proposalId: list[1]!.proposalId });
    expect(list[1]).toEqual(get);
    expect(Object.keys(list[0]!).sort()).toEqual(["approval", "error", "origin", "proposalId", "reason", "source", "status", "target", "value"]);
    expect(await forThread("th2")).toEqual([]);
    // The program changes under the proposal: it is reported stale.
    await t.run(async (c) => {
      const prog = await c.db.query("programs").withIndex("by_programId", (q) => q.eq("programId", programId)).unique();
      await c.db.patch(prog!._id, { rev: 2 });
    });
    expect((await forThread()).map((x) => x.status)).toEqual(["declined", "stale"]);
    await expect(t.query(api.queries.proposals.forThread, { token: "bad", threadId: "th1" })).rejects.toThrow(/unauthorized/);
  });

  it("the files of the thread reach build_program: a text as an attached file", async () => {
    const calls = stub([propose()]);
    await create("th1");
    const text = await t.run((c) => c.storage.store(new Blob(["Day A: squat 5x5 at 60 kg"], { type: "text/plain" })));
    await t.mutation(api.commands.files.register, { token: TOKEN, fileId: "f1", storageId: text, name: "program.txt", mime: "text/plain", size: 25 });
    await send("m1", "this is my program", "th1", ["f1"]);
    await settle(t);
    const build = calls.find((c) => c.job === "build_program")!;
    expect(build.input).toMatchObject({ attachedFiles: [{ name: "program.txt", text: expect.stringContaining("squat 5x5") }] });
    expect((await proposals())[0]!.status).toBe("ready");
  });

  it("the files of the thread reach build_program: a photo goes to the model as an image", async () => {
    const bodies: any[] = []; // eslint-disable-line @typescript-eslint/no-explicit-any
    vi.stubEnv("AI_PROVIDER", "openai");
    vi.stubEnv("OPENAI_API_KEY", "k");
    vi.stubEnv("OPENAI_MODEL", "m");
    vi.stubGlobal("fetch", async (_u: string, init: RequestInit) => {
      const b = JSON.parse(init.body as string);
      bodies.push(b);
      const job = b.messages[0].content.match(/^JOB: (\w+)/m)?.[1];
      const content = job === "chat_program" ? propose() : job === "build_program" ? JSON.stringify(MOCK_PROGRAM) : '{"summary":"s"}';
      return new Response(JSON.stringify({ choices: [{ message: { content } }] }), { status: 200 });
    });
    await create("th1");
    const img = await t.run((c) => c.storage.store(new Blob([new Uint8Array([1, 2, 3])], { type: "image/png" })));
    await t.mutation(api.commands.files.register, { token: TOKEN, fileId: "f2", storageId: img, name: "paper.png", mime: "image/png", size: 3 });
    await send("m1", "a photo of my program", "th1", ["f2"]);
    await settle(t);
    const build = bodies.find((b) => b.messages[0].content.includes("JOB: build_program"));
    expect(JSON.stringify(build.messages.at(-1).content)).toContain("data:image/png;base64,AQID");
    expect(JSON.stringify(build.messages.at(-1).content)).toContain("paper.png");
    expect((await proposals())[0]!.status).toBe("ready");
  });

  it("removing the program removes its thread and messages; other threads stay", async () => {
    const programId = await existingProgram();
    await create("th1", { about: { kind: "program", id: programId } });
    await create("th2", {});
    await send("m1", "hello", "th1");
    await send("m2", "hello", "th2");
    await settle(t);
    await t.mutation(api.commands.programs.remove, { token: TOKEN, programId });
    expect(await thread("th1")).toBeNull();
    expect(await messages("th1")).toEqual([]);
    expect(await thread("th2")).not.toBeNull();
    expect(await messages("th2")).toHaveLength(2);
  });
});
