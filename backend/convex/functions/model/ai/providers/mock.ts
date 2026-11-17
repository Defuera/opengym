import type { AiProvider, CompleteRequest } from "../provider";

type Data = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

const jobOf = (system: string) => system.match(/^JOB: (\w+)/m)?.[1] ?? "";

function inputOf(req: CompleteRequest): Data {
  const last = [...req.messages].reverse().find((m) => m.role === "user")?.content ?? "";
  const i = last.indexOf("INPUT_JSON:\n");
  if (i < 0) return {};
  try {
    return JSON.parse(last.slice(i + "INPUT_JSON:\n".length));
  } catch {
    return {};
  }
}

/**
 * Deterministic canned answers per job; needs no network or key.
 * Phase 1 jobs only. The chat, extraction, summary and import jobs come in phase 2.
 */
export class MockProvider implements AiProvider {
  readonly name = "mock";
  readonly supportsImages = true;

  async complete(req: CompleteRequest): Promise<string> {
    const job = jobOf(req.system);
    const d = inputOf(req);
    switch (job) {
      case "plan_session":
        return JSON.stringify({ rationale: "Mock plan: keeps your usual exercises.", exercises: d.suggestedStart?.exercises ?? [] });
      case "predict_activity":
        return JSON.stringify({ predictions: d.baseline ?? [{ kind: "gym", type: "Push", reason: "Mock rotation" }] });
      case "build_dashboard": {
        const goals: Data[] = (d.goals ?? []).filter((g: Data) => g.status === "active");
        return JSON.stringify({
          modules: [
            { type: "stat", which: "sessions" },
            { type: "stat", which: "active_days" },
            { type: "trend" },
            { type: "consistency" },
            ...goals.slice(0, 3).map((g) => ({ type: "goal_progress", goalId: g.id })),
            { type: "recent_sessions", limit: 5 },
          ],
        });
      }
      case "review_session":
        return JSON.stringify({ summary: "Mock review: solid session, repeat it next time.", changes: [] });
      default:
        throw new Error(`mock provider has no canned answer for job "${job}"`);
    }
  }
}
