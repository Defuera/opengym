import { learnPlaceJob } from "../../functions/model/ai/jobs/learnPlace";
import { type Logger, runJob } from "../../functions/model/ai/runJob";
import type { LearnSubject } from "../assertions/subject";
import { persona, placeOf } from "../fixtures";
import type { LearnCase } from "../types";
import type { CaseOutput, RunCtx } from "./types";

const silent: Logger = { info() {}, warn() {}, error() {} };
// The same limits as lib/placeFields (PLACE_TEXT_MAX, PLACE_QUOTE_MAX).
const TEXT_MAX = 1500;
const QUOTE_MAX = 300;

/** learn_place as the server does it, sentence by sentence: the note is written only on an AI answer with `changed`, cut to the limit, and carried to the next sentence. */
export async function runLearnPlace(c: LearnCase, ctx: RunCtx): Promise<CaseOutput> {
  const p = persona(c.persona);
  const place = placeOf(p, c.place);
  const others = p.places.filter((x) => x.placeId !== place.placeId).sort((a, b) => a.name.localeCompare(b.name)).map((x) => x.name);
  let note = place.text;
  const steps: LearnSubject["steps"] = [];
  const paths: ("ai" | "fallback")[] = [];
  const reasons: string[] = [];
  for (const sentence of c.sentences) {
    const quote = sentence.trim().slice(0, QUOTE_MAX);
    const before = note;
    const r = await runJob(learnPlaceJob, { place: { name: place.name, equipment: before }, otherPlaces: others, sentence: quote }, ctx.provider, silent, { timeoutMs: ctx.timeoutMs });
    paths.push(r.path);
    if (r.reason) reasons.push(r.reason);
    if (r.path === "ai" && r.value.changed) note = r.value.equipment.trim().slice(0, TEXT_MAX);
    steps.push({ sentence: quote, before, after: note });
  }
  return { subject: { job: "learn_place", startNote: place.text, steps }, paths, fallbackReasons: reasons, final: { startNote: place.text, steps } };
}
