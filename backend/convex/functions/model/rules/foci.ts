import type { Session } from "../schema";
import { starterFoci } from "./planner";

/** Gym foci in the log (any case is kept as written), oldest first by last use. */
export function loggedGymFoci(sessions: Session[]): string[] {
  const last = new Map<string, number>();
  for (const s of sessions) if (s.kind === "gym" && s.focus) last.set(s.focus, Math.max(last.get(s.focus) ?? 0, s.endedAt));
  return [...last.entries()].sort((a, b) => a[1] - b[1]).map(([f]) => f);
}

/** Every gym focus we keep a plan for: the ones in the log. The starter foci are used only while the log has none. */
export function knownGymFoci(sessions: Session[]): string[] {
  const logged = loggedGymFoci(sessions);
  return logged.length > 0 ? logged : [...starterFoci];
}

/**
 * Gym foci ordered by what is due: done longest ago first; never done first of all (starter order breaks ties).
 * The first one is the advised focus.
 */
export function gymFociByDue(sessions: Session[]): string[] {
  const last = new Map<string, number>();
  for (const s of sessions) if (s.kind === "gym" && s.focus) last.set(s.focus, Math.max(last.get(s.focus) ?? 0, s.endedAt));
  return knownGymFoci(sessions)
    .map((focus, index) => ({ focus, index, at: last.get(focus) ?? 0 }))
    .sort((a, b) => a.at - b.at || a.index - b.index)
    .map((x) => x.focus);
}
