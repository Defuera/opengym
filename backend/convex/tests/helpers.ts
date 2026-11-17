import { convexTest } from "convex-test";
import { vi } from "vitest";
import schema from "../functions/schema";

export const modules = import.meta.glob("../functions/**/*.ts");
export const TOKEN = "test-token";

/** Fresh in-memory deployment with the app token set and the AI off. */
export function setup() {
  vi.stubEnv("APP_TOKEN", TOKEN);
  vi.stubEnv("AI_PROVIDER", "none");
  return convexTest(schema, modules);
}
export type T = ReturnType<typeof setup>;

/** Run every scheduled function, including ones they schedule, advancing the fake clock. */
export const settle = (t: T) => t.finishAllScheduledFunctions(vi.runAllTimers);

/** A gym session in the shape the Convex command takes (`sessionId`, not `id`). */
export function pushSession(sessionId: string, endedAt: number, benchKg = 60, type = "Push") {
  return {
    sessionId,
    kind: "gym" as const,
    type,
    startedAt: Math.max(0, endedAt - 3_600_000),
    endedAt,
    exercises: [
      { name: "Bench press", sets: [{ reps: 6, kg: benchKg - 20, max: false }, { reps: 6, kg: benchKg, max: false }, { reps: 1, kg: benchKg, max: true }] },
      { name: "Dips", sets: [{ reps: 10, kg: 0, max: false }] },
    ],
    source: "app" as const,
  };
}

/** Stub the OpenAI chat endpoint. `reply` makes the text of each answer; calls are recorded. */
export function stubOpenAi(reply: (job: string, input: any) => string) { // eslint-disable-line @typescript-eslint/no-explicit-any
  vi.stubEnv("AI_PROVIDER", "openai");
  vi.stubEnv("OPENAI_API_KEY", "test-key");
  vi.stubEnv("OPENAI_MODEL", "test-model");
  const calls: { job: string; input: any }[] = []; // eslint-disable-line @typescript-eslint/no-explicit-any
  vi.stubGlobal("fetch", async (_url: string, init: RequestInit) => {
    const body = JSON.parse(init.body as string);
    const system: string = body.messages[0].content;
    const user: string = body.messages[body.messages.length - 1].content;
    const job = system.match(/^JOB: (\w+)/m)?.[1] ?? "";
    const raw = user.includes("INPUT_JSON:\n") ? user.slice(user.indexOf("INPUT_JSON:\n") + 12) : "{}";
    let input: unknown = {};
    try {
      input = JSON.parse(raw);
    } catch {
      /* retry turn: not data */
    }
    calls.push({ job, input });
    return new Response(JSON.stringify({ choices: [{ message: { content: reply(job, input) } }] }), { status: 200 });
  });
  return calls;
}
