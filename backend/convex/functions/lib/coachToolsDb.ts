import type { MutationCtx } from "../_generated/server";
import type { Doc } from "../_generated/dataModel";
import { allSessions, messageByMessageId } from "./db";
import { activeLimits } from "./limitsDb";
import { fileByFileId } from "./files";
import { PLACE_QUOTE_MAX, PLACE_TEXT_MAX } from "./placeFields";
import { placeByPlaceId, setPlaceText } from "./placesDb";
import { requestExerciseArt } from "./exerciseArtDb";
import { type ActionResult, type CoachAction, CoachActionSchema, editPlaceText, toPlanned } from "../model/coachTools";
import { type OneChange, type OpenExercise, addOne, rebuiltPlan, removeOne, replaceOne } from "../model/openSession";
import { finalizePlan } from "../model/proposals";
import type { Limit, PlanExercise, Session } from "../model/schema";

/** What the coach read when it made the actions: the open session it saw (id and rev), and the user message of the turn. */
export interface TurnBase {
  turnId: string;
  openSessionId?: string;
  rev?: number;
}

type Ctx = MutationCtx;
type Row = Doc<"openSession">;
type Evidence = "person_said" | "seen_in_photo";

const SESSION_TOOLS = new Set(["replace_open_exercise", "add_open_exercise", "remove_open_exercise", "rebuild_open_session"]);

/** Why the open session cannot be changed by this turn, or null. A stale rev or another session is refused (ADR-028: the phone wins). */
function sessionProblem(row: Row | null, base: TurnBase): string | null {
  if (!row || base.openSessionId === undefined) return "no session is open";
  if (row.id !== base.openSessionId) return "another session is open now";
  if (base.rev !== undefined && row.rev !== base.rev) return "the session changed since the coach read it";
  return null;
}

/** Why the person's message cannot be the evidence, or null. Only the person's own words or a photo of this turn count (ADR-021, ADR-032). */
async function evidenceProblem(ctx: Ctx, trigger: Doc<"messages"> | null, evidence: Evidence): Promise<string | null> {
  if (!trigger || trigger.role !== "user") return "no message of the person in this turn";
  if (evidence === "person_said") return trigger.text.trim() ? null : "the person said nothing in this turn";
  for (const id of trigger.fileIds) if ((await fileByFileId(ctx, id))?.kind === "image") return null;
  return "no photo in this turn";
}

/**
 * Does the actions of one coach turn, in order, in one transaction (ADR-032). Each action is checked again against the data now:
 * the zod shape, the session id and rev, the person's work, the plan safety limits and the avoid rules (ADR-004, ADR-015), the evidence
 * of a place change. A refused action changes nothing and says why. The session's place is never changed. The open session is
 * written once, with `rev + 1` and `updatedBy: "coach"`.
 */
export async function executeActions(ctx: Ctx, base: TurnBase, actions: unknown[]): Promise<ActionResult[]> {
  const results: ActionResult[] = [];
  const row = await ctx.db.query("openSession").first();
  const problem = sessionProblem(row, base);
  let exercises: OpenExercise[] = row?.exercises ?? [];
  let extra: { focus?: string; planNote?: string } = {};
  let changed = false;
  const trigger = await messageByMessageId(ctx, base.turnId);
  const seen = new Set<string>();
  let facts: { sessions: Session[]; limits: Limit[] } | null = null;
  // The plan safety limits and the avoid rules, as for any proposed plan. The weight cap reads the FULL history.
  const safe = async (list: PlanExercise[]) => {
    facts ??= { sessions: await allSessions(ctx), limits: await activeLimits(ctx) };
    return finalizePlan({ rationale: "", exercises: list }, facts.sessions, facts.limits).exercises;
  };
  const stamp = Date.now().toString(36);
  let n = 0;
  const newId = () => `${stamp}c${(n++).toString(36)}`;
  const art: string[] = [];

  for (const raw of actions) {
    const rawObj = (raw ?? {}) as { id?: unknown; name?: unknown };
    const actionId = typeof rawObj.id === "string" ? rawObj.id : "";
    const name = typeof rawObj.name === "string" ? rawObj.name : "";
    const reject = (reason: string) => results.push({ actionId, name, status: "rejected", reason });
    const parsed = CoachActionSchema.safeParse(raw);
    if (!parsed.success) {
      reject("invalid action");
      continue;
    }
    const a: CoachAction = parsed.data;
    if (seen.has(a.id)) {
      reject("the action id is used twice");
      continue;
    }
    seen.add(a.id);
    if (SESSION_TOOLS.has(a.name) && problem) {
      reject(problem);
      continue;
    }
    let change: OneChange | null = null;
    switch (a.name) {
      case "update_place": {
        const why = await evidenceProblem(ctx, trigger, a.arguments.evidence);
        const place = why ? null : await placeByPlaceId(ctx, a.arguments.placeId);
        if (why || !place) {
          reject(why ?? "no such place");
          continue;
        }
        const after = editPlaceText(place.text, a.arguments.add, a.arguments.remove);
        if (after.length > PLACE_TEXT_MAX) {
          reject(`the place text would be longer than ${PLACE_TEXT_MAX} characters`);
          continue;
        }
        const quote = (trigger!.text.trim() || "(photo)").slice(0, PLACE_QUOTE_MAX);
        const wrote = await setPlaceText(ctx, place, after, "chat", quote, undefined, a.arguments.evidence);
        results.push({ actionId: a.id, name: a.name, status: "applied", ...(wrote ? {} : { reason: "no change: the place text says it already" }) });
        continue;
      }
      case "replace_open_exercise":
      case "add_open_exercise": {
        const [ex] = await safe([a.arguments.exercise]);
        if (!ex) {
          reject("a limit marks this exercise avoid");
          continue;
        }
        change = a.name === "replace_open_exercise" ? replaceOne(exercises, a.arguments.exerciseId, toPlanned(ex), newId()) : addOne(exercises, toPlanned(ex), newId(), a.arguments.afterExerciseId);
        if (change.ok) art.push(ex.name.trim());
        break;
      }
      case "remove_open_exercise":
        change = removeOne(exercises, a.arguments.exerciseId);
        break;
      case "rebuild_open_session": {
        const list = await safe(a.arguments.exercises);
        if (list.length === 0) {
          reject("no exercise is left after the limits");
          continue;
        }
        const next = rebuiltPlan(exercises, list.map(toPlanned), newId, a.arguments.focus, a.arguments.planNote);
        change = { ok: true, exercises: next.exercises };
        extra = { ...extra, ...(next.focus !== undefined ? { focus: next.focus } : {}), ...(next.planNote !== undefined ? { planNote: next.planNote } : {}) };
        art.push(...list.map((e) => e.name.trim()));
        break;
      }
    }
    if (!change.ok) {
      reject(change.reason);
      continue;
    }
    exercises = change.exercises;
    changed = true;
    results.push({ actionId: a.id, name: a.name, status: "applied" });
  }

  if (changed && row) await ctx.db.patch(row._id, { exercises, ...extra, rev: row.rev + 1, updatedAt: Date.now(), updatedBy: "coach" });
  if (art.length > 0) await requestExerciseArt(ctx, [...new Set(art)].filter((x) => x.length > 0).slice(0, 12));
  return results;
}
