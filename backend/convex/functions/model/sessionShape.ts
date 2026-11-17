import { GYM_TYPE } from "./schema/common";
import type { Prediction } from "./schema";

/**
 * Activity first (ADR-013). A gym session has type "Gym"; the flavour is `focus`.
 * Old data and old app builds store the flavour in `type` ("Upper"). This turns that into the new shape:
 * kind gym, type != "Gym", no focus -> type "Gym", focus = old type. Idempotent.
 * A gym row that has both a focus and another type is not legacy; it is left as it is, so validation rejects it
 * instead of silently dropping the type.
 * Activity sessions are left alone. An empty type is left as it is, so validation still rejects it.
 */
export function normalizeSession<T extends { kind: string; type: string; focus?: string }>(s: T): T {
  if (s.kind !== "gym") return s;
  const t = s.type.trim();
  if (t === "") return s;
  if (t.toLowerCase() === GYM_TYPE.toLowerCase()) return s.type === GYM_TYPE ? s : { ...s, type: GYM_TYPE };
  if (s.focus !== undefined) return s;
  return { ...s, type: GYM_TYPE, focus: t };
}

/** True when `normalizeSession` would change the row (used by the migration). */
export const isLegacyGym = (s: { kind: string; type: string; focus?: string }): boolean => {
  const n = normalizeSession(s);
  return n.type !== s.type || n.focus !== s.focus;
};

/** Same for a stored or model prediction list: legacy gym items become Gym + focus, and Gym appears once (first wins). */
export function normalizePredictions(items: Prediction[]): Prediction[] {
  const out: Prediction[] = [];
  let gymSeen = false;
  for (const p of items) {
    const n = normalizeSession(p);
    if (n.kind === "gym") {
      if (gymSeen) continue;
      gymSeen = true;
    }
    out.push(n);
  }
  return out;
}
