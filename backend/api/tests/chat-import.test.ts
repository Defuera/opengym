import { afterEach, describe, expect, it } from "vitest";
import type { AiProvider } from "../src/ai/provider";
import { pushSession, setup } from "./helpers";

let h: ReturnType<typeof setup>;
afterEach(() => h?.cleanup());

describe("chat", () => {
  it("stores both messages, returns sources and extracts a context item", async () => {
    h = setup();
    await h.call("PUT", "/v1/sessions/p1", pushSession("p1", 5_000_000));
    await h.call("POST", "/v1/goals", { title: "Bench 80", kind: "strength", exercise: "Bench press", targetKg: 80 });
    const other = (await h.call("POST", "/v1/threads", { title: "Knee" })).json.thread;
    h.repos.threads.put({ ...other, summary: "Keeps squats light." });
    const t = (await h.call("POST", "/v1/threads", { title: "Legs day" })).json.thread;

    const r = (await h.call("POST", `/v1/threads/${t.id}/messages`, { text: "ankle felt tight after squats" })).json;
    expect(r.userMessage).toMatchObject({ role: "user", text: "ankle felt tight after squats" });
    expect(r.assistantMessage.role).toBe("assistant");
    expect(r.assistantMessage.sources).toEqual(expect.arrayContaining(["Knee thread", "gym log", "goals"]));
    expect(r.extracted.context).toHaveLength(1);
    expect(r.extracted.context[0]).toMatchObject({ topic: "ankle", source: "ai", threadId: t.id, active: true });
    expect((await h.call("GET", `/v1/threads/${t.id}/messages`)).json.messages).toHaveLength(2);
    expect((await h.call("GET", "/v1/context")).json.items).toHaveLength(1);

    const g = (await h.call("POST", `/v1/threads/${t.id}/messages`, { text: "I want to bench 90 kg" })).json;
    expect(g.extracted.goals[0]).toMatchObject({ kind: "strength", targetKg: 90, source: "ai" });
    await h.queue.drain();
    expect(h.repos.threads.get(t.id)?.summary).toContain("Mock summary");
    expect((await h.call("POST", "/v1/threads/nope/messages", { text: "hi" })).status).toBe(404);
  });
});

describe("AI failures fall back", () => {
  it("invalid JSON twice -> fallback path with rules output", async () => {
    let calls = 0;
    const bad: AiProvider = { name: "bad", supportsImages: false, complete: async () => (calls++, "this is not json") };
    h = setup({ provider: bad });
    const { plan } = (await h.call("GET", "/v1/plans/next?type=Pull")).json;
    expect(calls).toBe(2); // first try + one retry
    expect(plan.source).toBe("rules");
    expect(plan.exercises[0].name).toBe("Pull-up");
  });

  it("schema-invalid JSON and thrown errors also fall back", async () => {
    const wrong: AiProvider = { name: "wrong", supportsImages: false, complete: async () => JSON.stringify({ exercises: "nope" }) };
    h = setup({ provider: wrong });
    expect((await h.call("GET", "/v1/plans/next?type=Legs")).json.plan.source).toBe("rules");
    h.cleanup();
    const boom: AiProvider = { name: "boom", supportsImages: false, complete: async () => { throw new Error("network down"); } };
    h = setup({ provider: boom });
    expect((await h.call("GET", "/v1/plans/next?type=Legs")).json.plan.source).toBe("rules");
  });
});

describe("import", () => {
  const upload = (name: string, body: BlobPart, type: string) => {
    const f = new FormData();
    f.append("files", new File([body], name, { type }));
    return f;
  };

  it("imports a text file tagged with importId and DELETE removes everything", async () => {
    h = setup();
    const res = await h.call("POST", "/v1/import", upload("log.txt", "Push day: bench 6x40, 6x50", "text/plain"));
    expect(res.json.job.status).toBe("running");
    const id = res.json.job.id;
    await h.queue.drain();
    const job = (await h.call("GET", `/v1/import/${id}`)).json.job;
    expect(job).toMatchObject({ status: "done", total: 1, processed: 1, counts: { sessions: 1, goals: 1, context: 1 } });
    expect(job.notes.join(" ")).toMatch(/no date found.*upload time/);

    const sessions = (await h.call("GET", "/v1/sessions")).json.sessions;
    expect(sessions[0]).toMatchObject({ source: "import", importId: id, endedAt: h.clock.t });
    expect((await h.call("GET", "/v1/goals")).json.goals[0]).toMatchObject({ source: "import", importId: id });
    expect((await h.call("GET", "/v1/context")).json.items[0]).toMatchObject({ source: "import", importId: id });
    expect((await h.call("GET", "/v1/import")).json.jobs).toHaveLength(1);

    expect((await h.call("DELETE", `/v1/import/${id}`)).json).toEqual({ ok: true });
    expect((await h.call("GET", "/v1/sessions")).json.sessions).toHaveLength(0);
    expect((await h.call("GET", "/v1/goals")).json.goals).toHaveLength(0);
    expect((await h.call("GET", "/v1/context")).json.items).toHaveLength(0);
    expect((await h.call("DELETE", `/v1/import/${id}`)).status).toBe(404);
  });

  it("reads a photo into an activity session", async () => {
    h = setup();
    const id = (await h.call("POST", "/v1/import", upload("bike.png", new Uint8Array([1, 2, 3]), "image/png"))).json.job.id;
    await h.queue.drain();
    expect((await h.call("GET", "/v1/sessions")).json.sessions[0]).toMatchObject({ kind: "activity", type: "Cycle", minutes: 30, distanceKm: 12.5, importId: id, exercises: [] });
  });

  it("without AI nothing is imported and the note says why; large files are chunked and capped", async () => {
    h = setup({ provider: null });
    const id = (await h.call("POST", "/v1/import", upload("log.txt", "x", "text/plain"))).json.job.id;
    await h.queue.drain();
    const job = (await h.call("GET", `/v1/import/${id}`)).json.job;
    expect(job.status).toBe("done");
    expect(job.counts).toEqual({ sessions: 0, goals: 0, context: 0 });
    expect(job.notes.join(" ")).toContain("AI is required");
    h.cleanup();

    h = setup({ provider: null });
    const big = "a".repeat(12_000 * 45);
    const id2 = (await h.call("POST", "/v1/import", upload("big.txt", big, "text/plain"))).json.job.id;
    await h.queue.drain();
    const job2 = (await h.call("GET", `/v1/import/${id2}`)).json.job;
    expect(job2.total).toBe(40);
    expect(job2.notes.join(" ")).toContain("only the first 40 of 45 chunks");
  });

  it("uploads and serves files", async () => {
    h = setup();
    const f = new FormData();
    f.append("file", new File(["hello"], "n.txt", { type: "text/plain" }));
    const { file } = (await h.call("POST", "/v1/files", f)).json;
    expect(file).toMatchObject({ name: "n.txt", kind: "text", size: 5 });
    const res = await h.app.request(`/v1/files/${file.id}`, { headers: { authorization: "Bearer test-token" } });
    expect(await res.text()).toBe("hello");
  });
});
