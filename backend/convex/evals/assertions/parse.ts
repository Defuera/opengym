import { readKm, readMinutes } from "../../functions/model/ai/jobs/parseLog";
import { localDay } from "../../functions/model/logDate";
import { DAY_MS } from "../../functions/model/rules/util";
import type { Check } from "../types";
import type { Outcome } from "./build";
import type { ParseSubject } from "./subject";

const ok = (reason = "ok"): Outcome => ({ pass: true, reason });
const no = (reason: string): Outcome => ({ pass: false, reason });

/** Every number the text allows the model to give: the numbers written in it, and what the plain reader makes of "1h30" or "8 km". */
export function allowedNumbers(text: string): Set<number> {
  const out = new Set<number>();
  for (const m of text.matchAll(/\d+(?:[.,]\d+)?/g)) out.add(Number(m[0].replace(",", ".")));
  const mins = readMinutes(text);
  const km = readKm(text);
  if (mins !== null) out.add(mins);
  if (km !== null) out.add(km);
  return out;
}

/** The numbers of the AI answer that the text does not allow. */
export function inventedNumbers(s: ParseSubject): number[] {
  const p = s.parsed;
  if (!p) return [];
  const allowed = allowedNumbers(s.text);
  const given = [p.minutes, p.distanceKm, ...(p.exercises ?? []).flatMap((e) => (e.sets ?? []).flatMap((x) => ("reps" in x ? [x.reps, x.kg] : [x.minutes, x.distanceKm])))];
  return given.filter((n): n is number => n !== undefined && !allowed.has(n));
}

/** Checks that read a parse_log subject. Returns null when the check is not one of these kinds. */
export function parseCheck(c: Check, s: ParseSubject): Outcome | null {
  switch (c.kind) {
    case "parsedValue": {
      const got = s.found?.[c.field];
      if (c.absent) return got === undefined ? ok() : no(`${c.field} is ${got}, the text gives none`);
      if (got === undefined) return no(`${c.field} is missing, expected ${c.equals}`);
      return c.equals === undefined || Math.abs(got - c.equals) < 0.01 ? ok(`${c.field} ${got}`) : no(`${c.field} is ${got}, expected ${c.equals}`);
    }
    case "parsedDay": {
      const want = localDay(s.now - c.daysAgo * DAY_MS, "UTC");
      return s.day === want ? ok(s.day) : no(`the session is on ${s.day}, expected ${want}`);
    }
    case "parsedNothing": {
      const f = s.found ?? {};
      const given = [f.minutes !== undefined && `minutes ${f.minutes}`, f.distanceKm !== undefined && `km ${f.distanceKm}`, (f.exercises?.length ?? 0) > 0 && "exercises"].filter(Boolean);
      return given.length ? no(`the text has nothing to read, but the result has: ${given.join(", ")}`) : ok();
    }
    case "noInvented": {
      const bad = inventedNumbers(s);
      return bad.length ? no(`numbers that the text does not give: ${bad.join(", ")}`) : ok();
    }
    default:
      return null;
  }
}
