import type { ContextItem, Entry, Goal, Limit, Session } from "../functions/model/schema";

/** A keyword (matched as a whole word, case and hyphens ignored; a plural "s" is fine) or a regular expression. */
export type Pattern = string | { re: string; flags?: string };

/** A place of a persona. `text` is what the coach reads. `has` and `lacks` are what the checks use (truth). */
export interface EvalPlace {
  placeId: string;
  name: string;
  text: string;
  has: string[];
  lacks: string[];
}

export interface Persona {
  id: string;
  /** One line: who this is (for the report and the README). */
  about: string;
  sessions: Session[];
  goals: Goal[];
  limits: Limit[];
  context: ContextItem[];
  entries: Entry[];
  places: EvalPlace[];
}

export type Job = "build_session" | "chat" | "parse_log" | "learn_place";

/** Parts of an answer a text check can read. */
export type Field = "exerciseNames" | "planText" | "answer" | "answerHead" | "firstAnswer" | "type" | "rawType" | "focus" | "note";

/** A small declarative check. A new case is data: pick kinds here. `why` is shown in the report when the check fails. */
export type Check =
  | { kind: "contains"; field: Field; any?: Pattern[]; all?: Pattern[]; why?: string }
  | { kind: "notContains"; field: Field; any: Pattern[]; why?: string }
  | { kind: "count"; of: "exercises" | "sets"; min?: number; max?: number }
  /** The size of the final plan (2 minutes a set, a time entry its own minutes) and the `minutes` field must not pass `max`. */
  | { kind: "minutes"; max: number }
  | { kind: "equals"; field: "type" | "place" | "focus"; value: string }
  | { kind: "placeMatches"; re: string }
  | { kind: "noAvoided" }
  | { kind: "equipment" }
  | { kind: "parsedValue"; field: "minutes" | "distanceKm"; equals?: number; absent?: boolean }
  | { kind: "parsedDay"; daysAgo: number }
  | { kind: "parsedNothing" }
  | { kind: "noInvented" }
  | { kind: "noteUnchanged" }
  | { kind: "noteChanged" }
  | { kind: "claims"; item: Pattern; value: boolean }
  /** Chat: the answer must not repeat these (key phrases of the advice the person declined). */
  | { kind: "mustNotRepeat"; any: Pattern[] }
  /** Chat: the last answer must not copy a long stretch of an earlier answer (token overlap). A warning, never a gate. */
  | { kind: "similarity"; max: number };

interface CaseBase {
  id: string;
  family: string;
  /** What this case guards against, in one plain sentence. */
  about: string;
  persona: string;
  /** Must hold. Release needs 100%. */
  gates: Check[];
  /** What a right answer has (task success). */
  expect: Check[];
  /** Warnings only: shown in the report, never fail the case. */
  warn?: Check[];
}

export interface BuildCase extends CaseBase {
  job: "build_session";
  /** The activity the user chose. Null: a free request, the coach names the activity. */
  name: string | null;
  /** The note for today (named activity) or the free request text. */
  text: string;
  feedback?: string[];
  previousPlan?: unknown;
  /** Replaces the text the coach reads for a place (key: lower case place name). The truth lists `has`/`lacks` stay. */
  placeText?: Record<string, string>;
}

export interface ChatCase extends CaseBase {
  job: "chat";
  /** Fixed user messages. The coach answers each turn fresh; the history holds the coach's own earlier answers. */
  turns: string[];
  /** The place the thread is about, by lower case name. */
  place?: string;
}

export interface ParseCase extends CaseBase {
  job: "parse_log";
  activity: string;
  text: string;
}

export interface LearnCase extends CaseBase {
  job: "learn_place";
  /** The place the sentences are about, by lower case name. */
  place: string;
  /** Said one after the other; the note carries forward as the server does when it writes a change. */
  sentences: string[];
}

export type EvalCase = BuildCase | ChatCase | ParseCase | LearnCase;
