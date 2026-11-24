import type { AiProvider, CompleteRequest } from "../provider";
import { goalFromText } from "../../goalDraft";

/** The bytes the mock "draws": the 8-byte PNG signature, so tests need no image. */
export const MOCK_IMAGE = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

export const MOCK_TRANSCRIPT = "Mock voice: my left knee felt tight on squats today.";

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
 * Mock of the coach turn in the log chat: food words or a photo make a meal; "ran 5 km in 30 min" a run (with "yesterday" the day before);
 * "it was 6 km" changes the distance of the draft held in currentLogDraft; anything else is a plain note. It always drafts.
 */
function mockLogTurn(text: string, d: Data, photo: boolean): string {
  const now = Date.parse(String(d.now ?? new Date().toISOString()));
  const at = new Date(/\byesterday\b/i.test(text) ? now - 86_400_000 : now).toISOString();
  const km = text.match(/(\d+(?:\.\d+)?)\s*km/i);
  const min = text.match(/(\d+)\s*min/i);
  const was = d.currentLogDraft as Data | undefined;
  if (was?.session && km && !min) {
    const session = { ...was.session, distanceKm: Number(km[1]) };
    return JSON.stringify({ message: `Mock log: ${km[1]} km now.`, actions: [{ id: "a1", name: "draft_log", arguments: { kind: was.kind, summary: `${session.type}, ${km[1]} km in ${session.minutes} min`, at: was.at, session } }] });
  }
  if (/\bran\b|\brun\b/i.test(text) && (km || min)) {
    const session = { kind: "activity", type: "Run", ...(min ? { minutes: Number(min[1]) } : {}), ...(km ? { distanceKm: Number(km[1]) } : {}) };
    return JSON.stringify({ message: "Mock log: a run.", actions: [{ id: "a1", name: "draft_log", arguments: { kind: "training", summary: `Run${km ? `, ${km[1]} km` : ""}${min ? ` in ${min[1]} min` : ""}`, at, session } }] });
  }
  const meal = photo || /\b(lunch|dinner|breakfast|ate|snack)\b/i.test(text);
  return JSON.stringify({ message: `Mock log: ${meal ? "a meal" : "a note"}.`, actions: [{ id: "a1", name: "draft_log", arguments: { kind: meal ? "meal" : "other", summary: text.trim().slice(0, 100) || "A photo", at } }] });
}

/** The fixed valid answer of build_program: two weeks, one phase, sessions A and Bike (a week is A, Bike, A). */
export const MOCK_PROGRAM = {
  title: "Mock program",
  purpose: "A small fixed program for tests and offline runs.",
  startsOn: "2026-11-23",
  endsOn: "2026-12-06",
  week: ["A", "Bike", "A"],
  phases: [
    {
      title: "Base",
      weekFrom: 1,
      weekTo: 2,
      note: "",
      sessions: [
        { key: "A", title: "Session A", activity: "Gym", exercises: [{ name: "Squat", sets: [{ reps: 8, kg: 40, max: false }, { reps: 8, kg: 40, max: false }] }, { name: "Push-up", sets: [{ reps: 10, kg: 0, max: false }] }] },
        { key: "Bike", title: "Easy bike", activity: "Cycling", exercises: [{ name: "Bike", measure: "time", sets: [{ minutes: 30 }] }] },
      ],
    },
  ],
  rules: ["Stop a set when the knee hurts."],
  tests: ["Squat 10 reps at 40 kg without pain"],
  reason: "Mock proposal",
};

/**
 * Deterministic canned answers per job; needs no network or key.
 */
export class MockProvider implements AiProvider {
  readonly name = "mock";
  readonly supportsImages = true;

  async listModels(): Promise<string[]> {
    return [];
  }

  /** A fixed transcript, so tests need no audio. A file named "silence..." gives an empty one. */
  async transcribe(_bytes: Uint8Array, _mime: string, filename: string): Promise<string> {
    return /^silence/i.test(filename) ? "" : MOCK_TRANSCRIPT;
  }

  readonly imageModel = "mock-image";

  async image(): Promise<Uint8Array> {
    return MOCK_IMAGE;
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
      case "build_program":
        return JSON.stringify(MOCK_PROGRAM);
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
      case "summarise_thread": {
        const last = [...(d.messages ?? [])].reverse().find((m: Data) => m.role === "user");
        return JSON.stringify({ summary: `Mock summary: ${String(last?.text ?? d.title ?? "").slice(0, 300)}` });
      }
      case "import_data":
        if (d.hasImage) return JSON.stringify({ sessions: [{ kind: "activity", type: "Cycle", minutes: 30, distanceKm: 12.5 }], goals: [], context: [], notes: ["Mock read the machine screen."] });
        return JSON.stringify({
          sessions: [{ kind: "gym", type: "Gym", focus: "Push", exercises: [{ name: "Bench press", sets: [{ reps: 6, kg: 40 }, { reps: 6, kg: 50 }] }] }],
          goals: [{ title: "Bench press 80 kg", kind: "strength", exercise: "Bench press", targetKg: 80 }],
          context: [{ text: "Prefers short sessions", topic: "schedule" }],
          notes: [],
        });
      case "read_entry":
        return JSON.stringify({ kind: /lunch|dinner|breakfast|ate\b/i.test(String(d.text ?? "")) || d.photos > 0 ? "meal" : "other", summary: `Mock read: ${String(d.text ?? "").slice(0, 60) || "a photo"}` });
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
      case "coach_turn": {
        // Mock: "I have a <thing>" adds the thing to the session's place and swaps the exercise in view for one that uses it. Else a plain answer.
        const text = String([...req.messages].reverse().find((m) => m.role === "user")?.content ?? "").split("\n\nINPUT_JSON:")[0]!;
        if (d.screen === "log") return mockLogTurn(text, d, (req.images?.length ?? 0) > 0);
        if (d.screen === "program") return JSON.stringify(/\bprogram\b/i.test(text) ? { message: "Mock coach: I will write that program for you now.", actions: [{ id: "a1", name: "propose_program", arguments: { brief: "Write the program the person asked for." } }] } : { message: "Mock coach: noted. Tell me when you want a program.", actions: [] });
        if (d.screen === "goal") return JSON.stringify({ message: "Mock coach: here is the goal.", actions: [{ id: "a1", name: "draft_log", arguments: { summary: text.slice(0, 120), goal: goalFromText(text) } }] });
        const thing = text.match(/\bI (?:do )?have an? ([a-z][a-z ]{1,40}?)(?:[.,!]|$| at | here)/i)?.[1]?.trim();
        const place = (d.sessionPlace ?? d.placeInView) as Data | undefined;
        const current = (d.openSession?.exercises ?? []).find((e: Data) => e.id === d.currentExercise?.id && !e.personsWork);
        if (!thing || !place) return JSON.stringify({ message: "Mock coach: noted.", actions: [] });
        const name = thing.charAt(0).toUpperCase() + thing.slice(1);
        const actions: Data[] = [{ id: "a1", name: "update_place", arguments: { placeId: place.placeId, add: name, evidence: "person_said" } }];
        if (current) actions.push({ id: "a2", name: "replace_open_exercise", arguments: { exerciseId: current.id, exercise: { name: `${name} stand`, measure: "time", sets: [{ minutes: 1 }], note: `Mock: uses the ${thing}.` } } });
        return JSON.stringify({ message: `Mock coach: noted the ${thing} at ${place.name}.`, actions });
      }
      case "match_exercise": {
        // Mock: the first candidate whose name equals the exercise name (ignoring case and punctuation), else none.
        const same = (s: unknown) => String(s).toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
        const hit = (d.candidates ?? []).find((c: Data) => same(c.name) === same(d.exercise));
        return JSON.stringify({ id: hit ? hit.id : null });
      }
      case "review_session":
        return JSON.stringify({ summary: "Mock review: solid session, repeat it next time.", changes: [] });
      default:
        throw new Error(`mock provider has no canned answer for job "${job}"`);
    }
  }
}
