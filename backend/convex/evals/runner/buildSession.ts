import { buildSessionJob } from "../../functions/model/ai/jobs/buildSession";
import { type Logger, runJob } from "../../functions/model/ai/runJob";
import { lastPlaceIdFor } from "../../functions/model/places";
import { buildStartInput } from "../../functions/model/startInput";
import { checkedStartProposal, pickPlace, startOutcome } from "../../functions/model/startSave";
import { activityKey } from "../../functions/model/sessionShape";
import type { BuildSubject } from "../assertions/subject";
import { NOW, persona } from "../fixtures";
import type { BuildCase } from "../types";
import type { CaseOutput, RunCtx } from "./types";

const silent: Logger = { info() {}, warn() {}, error() {} };
const PLACE_NAME_MAX = 30; // the same cut as lib/placeFields

/** build_session as the server does it: the input from the full picture, runJob, the proposal step, the checks in code, the place. */
export async function runBuildSession(c: BuildCase, ctx: RunCtx): Promise<CaseOutput> {
  const p = persona(c.persona);
  const places = p.places.map((x) => ({ placeId: x.placeId, name: x.name, text: c.placeText?.[activityKey(x.name)] ?? x.text }));
  const limits = p.limits.filter((l) => l.status !== "cleared");
  const input = buildStartInput(
    { name: c.name ?? undefined, text: c.text, ...(c.feedback ? { feedback: c.feedback } : {}), ...(c.previousPlan ? { previousPlan: c.previousPlan } : {}) },
    { sessions: p.sessions, goals: p.goals, context: p.context, limits, places, entries: p.entries, now: NOW },
  );
  const r = await runJob(buildSessionJob, input.job, ctx.provider, silent, { timeoutMs: ctx.timeoutMs });
  const out = startOutcome(r, input);
  const base = { job: "build_session" as const, persona: p, limits, placeName: null, place: null, rawType: null, proposal: null };
  const paths: ("ai" | "fallback")[] = [r.path];
  const reasons = r.reason ? [r.reason] : [];
  if (out.failed) return { subject: base, paths, fallbackReasons: reasons, final: { status: "failed" } };
  const checked = checkedStartProposal({ name: c.name ?? undefined, text: c.text }, out.proposal, p.sessions, limits);
  const pick = pickPlace(places, out.proposal.place, lastPlaceIdFor(p.sessions, checked.type));
  const placeName = pick ? ("place" in pick ? pick.place.name : pick.newName.trim().replace(/\s+/g, " ").slice(0, PLACE_NAME_MAX).trim()) : null;
  const truth = placeName ? (p.places.find((x) => activityKey(x.name) === activityKey(placeName)) ?? null) : null;
  const subject: BuildSubject = { ...base, proposal: checked, placeName, place: truth, rawType: r.path === "ai" ? r.value.type : null };
  return { subject, paths, fallbackReasons: reasons, final: { status: "ready", source: out.source, place: placeName, proposal: checked } };
}
