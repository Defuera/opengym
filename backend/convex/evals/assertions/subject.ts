import type { Limit, StartProposal } from "../../functions/model/schema";
import type { ParsedLog } from "../../functions/model/ai/jobs/parseLog";
import type { EvalPlace, Field, Persona } from "../types";

/** What the user would see after the real pipeline, per job. The runner builds one; the checks read it. */
export interface BuildSubject {
  job: "build_session";
  persona: Persona;
  /** The place of the proposal, from the persona (truth lists), or null when the proposal has no place or an unknown one. */
  place: EvalPlace | null;
  placeName: string | null;
  /** Null when the request failed (a rebuild with no AI answer). */
  proposal: StartProposal | null;
  /** The type the AI gave before the server forced the name. */
  rawType: string | null;
  limits: Limit[];
}

export interface ChatSubject {
  job: "chat";
  persona: Persona;
  /** `actions`: the names of the functions the coach called in that turn. */
  turns: { user: string; assistant: string; actions?: string[] }[];
}

export interface ParseSubject {
  job: "parse_log";
  text: string;
  /** What the AI returned (after the zod shape), or the regex fallback. */
  parsed: ParsedLog | null;
  /** What the save step would write. */
  found: { minutes?: number; distanceKm?: number; focus?: string; exercises?: { name: string }[] } | null;
  /** The day the session ends up on, "YYYY-MM-DD". */
  day: string;
  now: number;
}

export interface LearnSubject {
  job: "learn_place";
  startNote: string;
  steps: { sentence: string; before: string; after: string }[];
}

export type Subject = BuildSubject | ChatSubject | ParseSubject | LearnSubject;

const planOf = (s: BuildSubject) => s.proposal?.plan?.exercises ?? [];

/** The text of one field. Empty string when the subject has no such field. */
export function fieldText(s: Subject, f: Field): string {
  if (s.job === "build_session") {
    const ex = planOf(s);
    if (f === "exerciseNames") return ex.map((e) => e.name).join("\n");
    if (f === "planText") return ex.map((e) => `${e.name} ${e.note ?? ""}`).join("\n");
    if (f === "type") return s.proposal?.type ?? "";
    if (f === "rawType") return s.rawType ?? "";
    if (f === "focus") return s.proposal?.focus ?? "";
    return "";
  }
  if (s.job === "chat") {
    const last = s.turns[s.turns.length - 1]?.assistant ?? "";
    if (f === "answer") return last;
    if (f === "answerHead") return last.slice(0, 200);
    if (f === "actions") return (s.turns[s.turns.length - 1]?.actions ?? []).join("\n");
    if (f === "firstAnswer") return s.turns[0]?.assistant ?? "";
    return "";
  }
  if (s.job === "parse_log") return f === "exerciseNames" ? (s.found?.exercises ?? []).map((e) => e.name).join("\n") : "";
  if (s.job === "learn_place") return f === "note" ? (s.steps[s.steps.length - 1]?.after ?? s.startNote) : "";
  return "";
}
