import type { Check } from "../types";
import type { Outcome } from "./build";
import { claimsItem } from "./equipment";
import type { ChatSubject, LearnSubject } from "./subject";
import { excerpt, hits, overlap, show } from "./text";

const ok = (reason = "ok"): Outcome => ({ pass: true, reason });
const no = (reason: string): Outcome => ({ pass: false, reason });

/** Checks that read a chat subject. Returns null when the check is not one of these kinds. */
export function chatCheck(c: Check, s: ChatSubject): Outcome | null {
  const last = s.turns[s.turns.length - 1]?.assistant ?? "";
  const earlier = s.turns.slice(0, -1).map((t) => t.assistant);
  switch (c.kind) {
    case "mustNotRepeat": {
      const again = hits(last, c.any);
      if (again.length === 0) return ok();
      const before = earlier.filter((a) => hits(a, again).length > 0).length;
      return no(`the answer says again ${again.map(show).join(", ")}${before ? " (the earlier answer said it)" : ""}: "${excerpt(last, 120)}"`);
    }
    case "similarity": {
      const worst = Math.max(0, ...earlier.map((a) => overlap(last, a)));
      return worst > c.max ? no(`${Math.round(worst * 100)}% of the answer's 4-word runs stand in an earlier answer, limit ${Math.round(c.max * 100)}%`) : ok(`${Math.round(worst * 100)}% overlap`);
    }
    default:
      return null;
  }
}

/** Checks that read a learn_place subject. Returns null when the check is not one of these kinds. */
export function learnCheck(c: Check, s: LearnSubject): Outcome | null {
  const end = s.steps[s.steps.length - 1]?.after ?? s.startNote;
  switch (c.kind) {
    case "noteUnchanged":
      return s.steps.every((x) => x.after === s.startNote) ? ok() : no(`the note changed: "${excerpt(end)}"`);
    case "noteChanged":
      return end !== s.startNote ? ok() : no("the note did not change");
    case "claims": {
      const has = claimsItem(end, c.item);
      return has === c.value ? ok() : no(c.value ? `the note does not say ${show(c.item)} is there: "${excerpt(end)}"` : `the note still says ${show(c.item)} is there: "${excerpt(end)}"`);
    }
    default:
      return null;
  }
}
