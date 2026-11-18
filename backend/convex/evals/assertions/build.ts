import { avoidedInPlan } from "../../functions/model/rules/limits";
import { MINUTES_PER_SET } from "../../functions/model/rules/planner";
import { activityKey } from "../../functions/model/sessionShape";
import type { Check } from "../types";
import { lackedIn } from "./equipment";
import type { BuildSubject } from "./subject";
import { hits } from "./text";

export interface Outcome {
  pass: boolean;
  reason: string;
}
const ok = (reason = "ok"): Outcome => ({ pass: true, reason });
const no = (reason: string): Outcome => ({ pass: false, reason });

const exercises = (s: BuildSubject) => s.proposal?.plan?.exercises ?? [];

/** The size of a plan in minutes by the same rule the server uses to fit it: a set costs MINUTES_PER_SET, a time entry its own minutes. */
export function estimateMinutes(s: BuildSubject): number {
  return exercises(s).reduce((n, e) => n + (e.measure === "time" ? e.sets.reduce((m, x) => m + x.minutes, 0) : e.sets.length * MINUTES_PER_SET), 0);
}

/** A movement the limits mark avoid: first by the real rule code (exact names), then by whole-phrase match, which also catches "Leg extensions". */
export function avoidedMovement(s: BuildSubject): string | null {
  const plan = s.proposal?.plan;
  if (!plan) return null;
  const real = avoidedInPlan(plan, s.limits);
  if (real) return real;
  const phrases = s.limits.filter((l) => l.status !== "cleared").flatMap((l) => l.rules.filter((r) => r.kind === "avoid").flatMap((r) => r.exercises ?? []));
  for (const e of plan.exercises) if (hits(e.name, phrases).length > 0) return e.name;
  return null;
}

/** Checks that read a build_session subject. Returns null when the check is not one of these kinds. */
export function buildCheck(c: Check, s: BuildSubject): Outcome | null {
  switch (c.kind) {
    case "noAvoided": {
      const hit = avoidedMovement(s);
      return hit ? no(`the plan has "${hit}", which a limit marks avoid`) : ok();
    }
    case "equipment": {
      if (!s.place) return no("the proposal has no known place, so equipment cannot be checked");
      const text = exercises(s).map((e) => `${e.name} ${e.note ?? ""}`).join("\n");
      const bad = lackedIn(text, s.place);
      return bad.length ? no(`the plan uses what "${s.place.name}" lacks: ${bad.join(", ")}`) : ok();
    }
    case "count": {
      const n = c.of === "exercises" ? exercises(s).length : exercises(s).reduce((m, e) => m + e.sets.length, 0);
      if (c.min !== undefined && n < c.min) return no(`${n} ${c.of}, needs at least ${c.min}`);
      if (c.max !== undefined && n > c.max) return no(`${n} ${c.of}, needs at most ${c.max}`);
      return ok(`${n} ${c.of}`);
    }
    case "minutes": {
      const est = estimateMinutes(s);
      const said = s.proposal?.minutes;
      if (est > c.max) return no(`the plan takes about ${est} min, limit ${c.max}`);
      if (said !== undefined && said > c.max) return no(`the proposal says ${said} min, limit ${c.max}`);
      return ok(`about ${est} min${said !== undefined ? `, says ${said}` : ""}`);
    }
    case "equals": {
      const got = c.field === "type" ? s.proposal?.type : c.field === "focus" ? s.proposal?.focus : s.placeName;
      const same = c.field === "type" ? got === c.value : got !== undefined && got !== null && activityKey(got) === activityKey(c.value);
      return same ? ok() : no(`${c.field} is ${got === undefined || got === null ? "missing" : `"${got}"`}, expected "${c.value}"`);
    }
    case "placeMatches":
      return s.placeName && new RegExp(c.re, "i").test(s.placeName) ? ok(s.placeName) : no(`place is ${s.placeName ? `"${s.placeName}"` : "missing"}, expected /${c.re}/`);
    default:
      return null;
  }
}
