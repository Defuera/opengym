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

const BODY_PART = /\b(ankle|knee|shoulder|back|wrist|elbow|hip|neck|calf|hamstring)\b/i;

/** Mock of extract_from_chat: a body part with "tight/sore/..." becomes a context note; "I want to ..." becomes a goal. */
function extract(text: string) {
  const context: { text: string; topic: string }[] = [];
  const goals: { title: string; kind: string; exercise?: string; targetKg?: number }[] = [];
  const part = text.match(BODY_PART);
  if (part && /(tight|sore|stiff|felt|hurt|pinch|dislike)/i.test(text)) context.push({ text: text.slice(0, 300), topic: part[1]!.toLowerCase() });
  const want = text.match(/\bi want to ([^.!?]+)/i);
  if (want) {
    const bench = want[1]!.match(/bench(?: press)?\D+(\d+(?:\.\d+)?)\s*kg/i);
    goals.push(bench ? { title: `Bench press ${bench[1]} kg`, kind: "strength", exercise: "Bench press", targetKg: Number(bench[1]) } : { title: want[1]!.trim().slice(0, 80), kind: "custom" });
  }
  return { goals, context };
}

/**
 * Deterministic canned answers per job; needs no network or key.
 */
export class MockProvider implements AiProvider {
  readonly name = "mock";
  readonly supportsImages = true;

  async listModels(): Promise<string[]> {
    return [];
  }

  async complete(req: CompleteRequest): Promise<string> {
    const job = jobOf(req.system);
    const d = inputOf(req);
    switch (job) {
      case "plan_session":
        return JSON.stringify({ rationale: "Mock plan: keeps your usual exercises.", exercises: d.suggestedStart?.exercises ?? [] });
      case "build_session": {
        const first = String(d.request ?? "").split(",")[0]!.trim();
        const type = String(d.activity ?? (first ? first.charAt(0).toUpperCase() + first.slice(1) : "Gym")).slice(0, 40);
        return JSON.stringify({ kind: "gym", type, reason: "Mock proposal", plan: { rationale: "Mock plan: a simple bodyweight session.", exercises: [{ name: "Push-up", sets: [{ reps: 10, kg: 0, max: false }] }, { name: "Squat", sets: [{ reps: 15, kg: 0, max: false }] }] } });
      }
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
      case "chat":
        return "Mock coach: noted. Keep your next session simple and stick to the plan.";
      case "extract_from_chat":
        return JSON.stringify(extract(String(d.message ?? "")));
      case "summarise_thread": {
        const last = [...(d.messages ?? [])].reverse().find((m: Data) => m.role === "user");
        return JSON.stringify({ summary: `Mock summary: ${String(last?.text ?? d.title ?? "").slice(0, 300)}` });
      }
      case "title_thread":
        return JSON.stringify({ title: `"Mock title: ${String(d.text ?? "").slice(0, 20)}".` });
      case "import_data":
        if (d.hasImage) return JSON.stringify({ sessions: [{ kind: "activity", type: "Cycle", minutes: 30, distanceKm: 12.5 }], goals: [], context: [], notes: ["Mock read the machine screen."] });
        return JSON.stringify({
          sessions: [{ kind: "gym", type: "Gym", focus: "Push", exercises: [{ name: "Bench press", sets: [{ reps: 6, kg: 40 }, { reps: 6, kg: 50 }] }] }],
          goals: [{ title: "Bench press 80 kg", kind: "strength", exercise: "Bench press", targetKg: 80 }],
          context: [{ text: "Prefers short sessions", topic: "schedule" }],
          notes: [],
        });
      case "parse_log": {
        // Reads "45 min", "8 km", "yesterday", "easy" and the names of the log's exercises it finds in the text. No sets: the code fills the usual ones.
        const text = String(d.text ?? "");
        const min = text.match(/(\d+)\s*min/i);
        const km = text.match(/(\d+(?:\.\d+)?)\s*km/i);
        const names: string[] = (d.exercisesTheUserKnows ?? []).map((e: Data) => String(e.name)).filter((n: string) => text.toLowerCase().includes(n.toLowerCase()));
        const day = /\byesterday\b/i.test(text) ? new Date(Date.parse(String(d.today).slice(0, 10)) - 86_400_000).toISOString().slice(0, 10) : undefined;
        return JSON.stringify({
          ...(min ? { minutes: Number(min[1]) } : {}),
          ...(km ? { distanceKm: Number(km[1]) } : {}),
          ...(/\beasy\b/i.test(text) ? { focus: "Easy" } : {}),
          ...(day ? { date: day } : {}),
          ...(names.length > 0 ? { exercises: names.map((name) => ({ name })) } : {}),
        });
      }
      case "learn_place": {
        // Mock: a sentence that names a piece of equipment is added to the note as it is; anything else changes nothing.
        const sentence = String(d.sentence ?? "");
        const now = String(d.place?.equipment ?? "");
        if (!/\b(dumbbells?|barbells?|kettlebells?|bands?|rack|bench|machines?|bar|mat|rower|treadmill)\b/i.test(sentence)) return JSON.stringify({ changed: false, equipment: now });
        return JSON.stringify({ changed: true, equipment: (now ? `${now}. ${sentence}` : sentence).slice(0, 1500) });
      }
      case "review_session":
        return JSON.stringify({ summary: "Mock review: solid session, repeat it next time.", changes: [] });
      default:
        throw new Error(`mock provider has no canned answer for job "${job}"`);
    }
  }
}
