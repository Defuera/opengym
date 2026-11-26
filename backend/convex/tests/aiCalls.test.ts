import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { z } from "zod";
import { internal } from "../functions/_generated/api";
import { AI_CALL_KEEP_MS, AI_CALL_TEXT_MAX } from "../functions/lib/constants";
import type { AiProvider } from "../functions/model/ai/provider";
import { type JobDef, type JobTrace, runJob, silentLogger } from "../functions/model/ai/runJob";
import { setup, type T } from "./helpers";

/** ADR-027: every AI job run is stored (the prompt, every attempt, the outcome) and erased after 90 days. */
const job: JobDef<{ q: string }, { a: string }> = {
  name: "test_job",
  description: "",
  fallbackDescription: "",
  json: true,
  maxTokens: 100,
  output: z.object({ a: z.string().max(5) }),
  build: (i) => ({ system: "SYS", messages: [{ role: "user", content: i.q }] }),
  fallback: () => ({ a: "code" }),
};
const provider = (replies: (string | Error)[]): AiProvider => ({
  name: "fake",
  supportsImages: false,
  listModels: async () => [],
  complete: async () => {
    const r = replies.shift();
    if (r instanceof Error) throw r;
    return r ?? "";
  },
});
const traced = async (p: AiProvider | null) => {
  let trace: JobTrace | null = null;
  const result = await runJob(job, { q: "hello" }, p, silentLogger, { onTrace: (t) => (trace = t) });
  return { result, trace: trace as JobTrace | null };
};

describe("the trace of a job run", () => {
  it("holds the prompt and the one good attempt", async () => {
    const { result, trace } = await traced(provider(['{"a":"ok"}']));
    expect(result.path).toBe("ai");
    expect(trace).toMatchObject({ job: "test_job", system: "SYS", messages: [{ role: "user", content: "hello" }], images: 0, path: "ai" });
    expect(trace!.attempts).toHaveLength(1);
    expect(trace!.attempts[0]).toMatchObject({ raw: '{"a":"ok"}' });
    expect(trace!.attempts[0]!.error).toBeUndefined();
  });

  it("keeps the rejected first answer with the reason, then the retry", async () => {
    const { trace } = await traced(provider(['{"a":"too long"}', '{"a":"ok"}']));
    expect(trace!.path).toBe("ai");
    expect(trace!.attempts).toHaveLength(2);
    expect(trace!.attempts[0]!.raw).toBe('{"a":"too long"}');
    expect(trace!.attempts[0]!.error).toMatch(/invalid output/);
    expect(trace!.attempts[1]!.error).toBeUndefined();
  });

  it("keeps a failed request and the fallback reason", async () => {
    const { result, trace } = await traced(provider([new Error("HTTP 500"), "not json"]));
    expect(result.path).toBe("fallback");
    expect(trace!.path).toBe("fallback");
    expect(trace!.attempts.map((a) => a.error)).toEqual(["HTTP 500", expect.any(String)]);
    expect(trace!.attempts[1]!.raw).toBe("not json");
  });

  it("gives no trace when no call was made", async () => {
    expect((await traced(null)).trace).toBeNull();
  });

  it("does not fail the job when the trace handler throws", async () => {
    const r = await runJob(job, { q: "x" }, provider(['{"a":"ok"}']), silentLogger, { onTrace: () => { throw new Error("boom"); } });
    expect(r.path).toBe("ai");
  });
});

describe("stored AI calls", () => {
  const NOW = Date.UTC(2026, 10, 21, 12);
  let t: T;
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(NOW);
    t = setup();
  });
  afterEach(() => vi.useRealTimers());
  const rows = () => t.run((c) => c.db.query("aiCalls").collect());
  const save = (system = "SYS") => t.mutation(internal.jobs.aiCalls.save, { userId: "owner", job: "build_session", provider: "openai", model: "m", system, messages: [{ role: "user", content: "in" }], images: 0, attempts: [{ raw: "out", ms: 5 }], path: "ai", ms: 5 });

  it("stores a call with its time and cuts a very long text", async () => {
    await save("x".repeat(AI_CALL_TEXT_MAX + 10));
    const [row] = await rows();
    expect(row).toMatchObject({ at: NOW, job: "build_session", model: "m", path: "ai" });
    expect(row!.system).toHaveLength(AI_CALL_TEXT_MAX);
  });

  it("erases a call after 90 days, not before", async () => {
    await save();
    vi.setSystemTime(NOW + AI_CALL_KEEP_MS - 1000);
    await t.mutation(internal.jobs.purge.run, {});
    expect(await rows()).toHaveLength(1);
    vi.setSystemTime(NOW + AI_CALL_KEEP_MS + 1000);
    expect((await t.mutation(internal.jobs.purge.run, {})).aiCalls).toBe(1);
    expect(await rows()).toHaveLength(0);
  });
});
