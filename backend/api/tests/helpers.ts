import { buildApp } from "../src/app";
import type { AiProvider } from "../src/ai/provider";
import { MockProvider } from "../src/ai/providers/mock";
import { createAiRunner, silentLogger } from "../src/ai/run-job";
import { createTempRepositories } from "../src/repositories/temp";
import { createTaskQueue } from "../src/services/queue";
import type { Session } from "../src/schema";

export const TOKEN = "test-token";

export function setup(opts: { provider?: AiProvider | null; autoRun?: boolean } = {}) {
  const { repos, cleanup } = createTempRepositories();
  const queue = createTaskQueue(silentLogger, opts.autoRun ?? false);
  const provider = opts.provider === undefined ? new MockProvider() : opts.provider;
  const clock = { t: Date.UTC(2026, 0, 15, 12) };
  const { app, ctx } = buildApp({ token: TOKEN, version: "test", repos, ai: createAiRunner(provider, silentLogger), queue, logger: silentLogger, now: () => clock.t });

  const call = async (method: string, path: string, body?: unknown, headers: Record<string, string> = { authorization: `Bearer ${TOKEN}` }) => {
    const init: RequestInit = { method, headers: { ...headers } };
    if (body instanceof FormData) init.body = body;
    else if (body !== undefined) {
      init.body = JSON.stringify(body);
      (init.headers as Record<string, string>)["content-type"] = "application/json";
    }
    const res = await app.request(path, init);
    const json = res.headers.get("content-type")?.includes("json") ? await res.json() : null;
    return { status: res.status, json: json as any }; // eslint-disable-line @typescript-eslint/no-explicit-any
  };
  return { app, ctx, repos, queue, clock, call, cleanup };
}

export function pushSession(id: string, endedAt: number, benchKg = 60): Session {
  return {
    id,
    kind: "gym",
    type: "Push",
    startedAt: Math.max(0, endedAt - 3_600_000),
    endedAt,
    exercises: [
      { name: "Bench press", sets: [{ reps: 6, kg: benchKg - 20, max: false }, { reps: 6, kg: benchKg, max: false }, { reps: 1, kg: benchKg, max: true }] },
      { name: "Dips", sets: [{ reps: 10, kg: 0, max: false }] },
    ],
    source: "app",
  };
}
