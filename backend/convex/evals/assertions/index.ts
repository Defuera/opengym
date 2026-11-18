import { StartProposalSchema } from "../../functions/model/schema";
import { LearnPlaceSchema } from "../../functions/model/ai/jobs/learnPlace";
import { ParsedLogSchema } from "../../functions/model/ai/jobs/parseLog";
import type { Check, Job } from "../types";
import { type Outcome, buildCheck } from "./build";
import { chatCheck, learnCheck } from "./chatPlace";
import { parseCheck } from "./parse";
import { type Subject, fieldText } from "./subject";
import { excerpt, hits, show } from "./text";

export interface CheckResult {
  /** A short name of the check, for the report. */
  name: string;
  pass: boolean;
  reason: string;
}

export const checkName = (c: Check): string => {
  switch (c.kind) {
    case "contains":
    case "notContains":
      return `${c.kind} ${c.field}${c.why ? ` (${c.why})` : ""}`;
    case "count":
      return `count ${c.of}`;
    case "equals":
      return `equals ${c.field}`;
    case "claims":
      return `${c.value ? "claims" : "does not claim"} ${show(c.item)}`;
    case "parsedValue":
      return `parsed ${c.field}`;
    default:
      return c.kind;
  }
};

function textCheck(c: Check, s: Subject): Outcome | null {
  if (c.kind === "contains") {
    const text = fieldText(s, c.field);
    const miss = [...(c.any && c.any.length > 0 && hits(text, c.any).length === 0 ? [`any of ${c.any.map(show).join(" ")}`] : []), ...(c.all ?? []).filter((p) => hits(text, [p]).length === 0).map(show)];
    return miss.length ? { pass: false, reason: `${c.field} lacks ${miss.join(", ")}: "${excerpt(text, 120)}"` } : { pass: true, reason: "ok" };
  }
  if (c.kind === "notContains") {
    const found = hits(fieldText(s, c.field), c.any);
    return found.length ? { pass: false, reason: `${c.field} has ${found.map(show).join(", ")}: "${excerpt(fieldText(s, c.field), 120)}"` } : { pass: true, reason: "ok" };
  }
  return null;
}

/** Runs one declarative check on what the user would see. A check that does not fit the job fails with a clear reason (a case-authoring error). */
export function evaluate(c: Check, s: Subject): CheckResult {
  const o =
    textCheck(c, s) ??
    (s.job === "build_session" ? buildCheck(c, s) : s.job === "chat" ? chatCheck(c, s) : s.job === "parse_log" ? parseCheck(c, s) : learnCheck(c, s)) ??
    { pass: false, reason: `check "${c.kind}" does not apply to job ${s.job}` };
  return { name: checkName(c), ...o };
}

export const evaluateAll = (cs: Check[], s: Subject): CheckResult[] => cs.map((c) => evaluate(c, s));

/**
 * The checks every case gets. "valid_output": the final output has the right shape. "model_answered": every call ended on the AI path
 * (a fallback means the model failed twice or timed out, and the plain code answered).
 */
export function implicitGates(s: Subject, paths: ("ai" | "fallback")[]): CheckResult[] {
  let valid: Outcome;
  if (s.job === "build_session") valid = s.proposal ? (StartProposalSchema.safeParse(s.proposal).success ? { pass: true, reason: "ok" } : { pass: false, reason: "the final proposal breaks the shape" }) : { pass: false, reason: "the request failed (no AI answer on a rebuild)" };
  else if (s.job === "chat") valid = s.turns.length > 0 && s.turns.every((t) => t.assistant.trim() !== "") ? { pass: true, reason: "ok" } : { pass: false, reason: "an answer is empty" };
  else if (s.job === "parse_log") valid = s.parsed && ParsedLogSchema.safeParse(s.parsed).success ? { pass: true, reason: "ok" } : { pass: false, reason: "no valid parse" };
  else valid = s.steps.every((x) => LearnPlaceSchema.shape.equipment.safeParse(x.after).success) ? { pass: true, reason: "ok" } : { pass: false, reason: "a note is longer than 1500 characters" };
  const fb = paths.filter((p) => p === "fallback").length;
  return [
    { name: "valid_output", ...valid },
    { name: "model_answered", pass: fb === 0, reason: fb === 0 ? "ok" : `${fb} of ${paths.length} calls ended on the plain-code fallback` },
  ];
}

/** Which kinds of check read which job (used by the tests that check every case is well formed). */
export const KINDS_BY_JOB: Record<Job, Check["kind"][]> = {
  build_session: ["contains", "notContains", "count", "minutes", "equals", "placeMatches", "noAvoided", "equipment"],
  chat: ["contains", "notContains", "mustNotRepeat", "similarity"],
  parse_log: ["parsedValue", "parsedDay", "parsedNothing", "noInvented", "contains", "notContains"],
  learn_place: ["contains", "notContains", "noteUnchanged", "noteChanged", "claims"],
};
