import type { EvalPlace, Pattern } from "../types";
import { hits, show } from "./text";

/** The keywords of the place's `lacks` list that the text names. Empty list = the text uses nothing the place lacks. */
export function lackedIn(text: string, place: Pick<EvalPlace, "lacks">): string[] {
  return hits(text, place.lacks).map(show);
}

const NEGATION = /\b(no|not|without|gone|broken|removed|lost|sold|out of|isn't|don't|doesn't|never|lack|lacks|lacking)\b/i;

/** True when a clause of the note names the item as present: a clause that holds the item and no negation word. */
export function claimsItem(note: string, item: Pattern): boolean {
  return note
    .split(/[.;\n]+/)
    .flatMap((s) => s.split(/,(?!\s*\d)/))
    .some((clause) => hits(clause, [item]).length > 0 && !NEGATION.test(clause));
}
