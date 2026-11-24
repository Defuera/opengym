import type { Limit, PlanDraft, PromptLimit, Session } from "../schema";
import { type LimitForAi, RECORDS_PER_LIMIT_MAX, RECORD_PROMPT_MAX_CHARS } from "../schema/limits";
import { type MuscleKey, allMusclesFor, normName } from "./muscles";

type Loaders = { muscles: MuscleKey[]; activities: string[]; anyActivity?: boolean };

const KNEE: Loaders = { muscles: ["quads", "hamstrings", "glutes", "calves", "hips"], activities: ["run", "cycling"], anyActivity: true };
const ARM_JOINT: Loaders = { muscles: ["chest", "shoulders", "biceps", "triceps", "forearms", "lats", "upper_back"], activities: ["bouldering"] };
const SHOULDER: Loaders = { muscles: ["shoulders", "chest", "lats", "upper_back", "triceps", "biceps"], activities: ["swim", "bouldering"] };
const ANKLE: Loaders = { muscles: ["calves", "quads"], activities: ["run"] };

/** What loads each limit part. A muscle part not listed here is loaded by training that muscle (see loaders()). */
const LOADERS: Record<string, Loaders> = {
  left_knee: KNEE,
  right_knee: KNEE,
  left_wrist: ARM_JOINT,
  right_wrist: ARM_JOINT,
  wrists: ARM_JOINT,
  left_elbow: ARM_JOINT,
  right_elbow: ARM_JOINT,
  left_shoulder: SHOULDER,
  right_shoulder: SHOULDER,
  shoulders: SHOULDER,
  lower_back: { muscles: ["lower_back", "glutes", "hamstrings", "quads"], activities: [] },
  left_ankle: ANKLE,
  right_ankle: ANKLE,
  neck: { muscles: ["upper_back", "shoulders"], activities: [] },
};

const ACTIVITY_MUSCLES: Record<string, MuscleKey[]> = {
  run: ["quads", "hamstrings", "calves", "glutes"],
  cycling: ["quads", "calves"],
};

function loaders(part: string): Loaders {
  return LOADERS[part] ?? { muscles: [part as MuscleKey], activities: Object.entries(ACTIVITY_MUSCLES).filter(([, ms]) => ms.includes(part as MuscleKey)).map(([a]) => a) };
}

/** True when the session trained a muscle next to the part, or is an activity that uses it. */
export function sessionLoadsPart(session: Session, part: string): boolean {
  const l = loaders(part);
  if (session.kind === "gym") {
    const trained = new Set(session.exercises.flatMap((e) => allMusclesFor(e.name)));
    return l.muscles.some((k) => trained.has(k));
  }
  return l.anyActivity === true || l.activities.includes(session.type.toLowerCase());
}

/** The non-cleared limits this session loads. */
export const limitsLoadedBy = <L extends { part: string; status: string }>(session: Session, limits: L[]): L[] =>
  limits.filter((l) => l.status !== "cleared" && sessionLoadsPart(session, l.part));

/**
 * What an AI job reads of a limit (ADR-033): the rules as kind and text (no exercise lists) and the person's records, word for word.
 * A cleared limit gives no rules; it is kept only when it has records, so the coach can still report them.
 */
export const limitsForPrompt = (limits: LimitForAi[]): PromptLimit[] =>
  limits.flatMap((l) => {
    const records = (l.records ?? []).slice(0, RECORDS_PER_LIMIT_MAX).map((r) => (r.text.length > RECORD_PROMPT_MAX_CHARS ? { ...r, text: r.text.slice(0, RECORD_PROMPT_MAX_CHARS), textWasCut: true as const } : r));
    const cleared = l.status === "cleared";
    if (cleared && records.length === 0) return [];
    return [{ part: l.part, title: l.title, status: l.status, rules: cleared ? [] : l.rules.map((r) => ({ kind: r.kind, text: r.text })), ...(records.length > 0 ? { records } : {}) }];
  });

/** Exercise names (normalised) that a non-cleared limit says to avoid. */
export function avoidedExercises(limits: Limit[]): Set<string> {
  const out = new Set<string>();
  for (const l of limits) {
    if (l.status === "cleared") continue;
    for (const r of l.rules) if (r.kind === "avoid") for (const e of r.exercises ?? []) out.add(normName(e));
  }
  return out;
}

/** Hard check: the first plan exercise that an avoid rule names, or null. */
export function avoidedInPlan(draft: PlanDraft, limits: Limit[]): string | null {
  const avoid = avoidedExercises(limits);
  return draft.exercises.find((e) => avoid.has(normName(e.name)))?.name ?? null;
}

/** The plan without the avoided exercises. */
export function dropAvoided(draft: PlanDraft, limits: Limit[]): PlanDraft {
  const avoid = avoidedExercises(limits);
  return avoid.size === 0 ? draft : { ...draft, exercises: draft.exercises.filter((e) => !avoid.has(normName(e.name))) };
}
