import { GYM_TYPE } from "./schema/common";
import type { Prediction } from "./schema";

/**
 * The matching key of an activity or focus name (ADR-016): lower case, trimmed, inner whitespace collapsed.
 * Two names with the same key are the same activity; display uses the most recent spelling in the log.
 */
export const activityKey = (name: string): string => name.trim().replace(/\s+/g, " ").toLowerCase();

/**
 * The flavour names an old app build stored in `type` of a gym session ("Upper", "Legs", ...), before ADR-013.
 * This is a frozen compatibility list for reading old rows and old outbox payloads, not a product list:
 * nothing offers these names to the user. Any other name of a set-based session is an activity name (ADR-016).
 */
const LEGACY_GYM_FLAVOURS = new Set(
  ["push", "pull", "legs", "upper", "lower", "full body", "upper body", "lower body", "arms", "chest", "back", "shoulders", "core", "abs"],
);

/**
 * Reads the shape of a session row (ADR-013 + ADR-016).
 * - kind gym ("a session with sets"): `type` is the activity name, any text 1..40 ("Gym", "Home", ...). It is trimmed;
 *   "gym" in any case becomes "Gym".
 * - Legacy: a gym row whose type is an old flavour name and that has no focus ("Upper") becomes type "Gym", focus "Upper".
 *   Idempotent. An old row with both a focus and a flavour in `type` is now simply an activity with a focus.
 * - Activity sessions are left alone. An empty type is left as it is, so validation still rejects it.
 */
export function normalizeSession<T extends { kind: string; type: string; focus?: string }>(s: T): T {
  if (s.kind !== "gym") return s;
  const t = s.type.trim();
  if (t === "") return s;
  if (t.toLowerCase() === GYM_TYPE.toLowerCase()) return s.type === GYM_TYPE ? s : { ...s, type: GYM_TYPE };
  if (s.focus === undefined && LEGACY_GYM_FLAVOURS.has(activityKey(t))) return { ...s, type: GYM_TYPE, focus: t };
  return s.type === t ? s : { ...s, type: t };
}

/** True when `normalizeSession` would change the row (used by the migration). */
export const isLegacyGym = (s: { kind: string; type: string; focus?: string }): boolean => {
  const n = normalizeSession(s);
  return n.type !== s.type || n.focus !== s.focus;
};

/** At most this many items per activity, and in total (the start proposals). */
export const MAX_PREDICTIONS = 6;
export const MAX_PREDICTIONS_PER_ACTIVITY = 2;

/**
 * Same for a stored or model prediction list: legacy gym items become the new shape, an exact repeat (same kind,
 * activity and focus) is dropped, at most 2 items per activity and 6 in total. The first ones win.
 * The log is not checked here (see rules/predictions.ts validatePredictions).
 */
export function normalizePredictions(items: Prediction[]): Prediction[] {
  const out: Prediction[] = [];
  const seen = new Set<string>();
  const perActivity = new Map<string, number>();
  for (const p of items) {
    const n = normalizeSession(p);
    const a = `${n.kind}:${activityKey(n.type)}`;
    const id = `${a}:${activityKey(n.focus ?? "")}`;
    if (seen.has(id) || (perActivity.get(a) ?? 0) >= MAX_PREDICTIONS_PER_ACTIVITY || out.length >= MAX_PREDICTIONS) continue;
    seen.add(id);
    perActivity.set(a, (perActivity.get(a) ?? 0) + 1);
    out.push(n);
  }
  return out;
}
