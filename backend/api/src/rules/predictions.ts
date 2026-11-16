import type { Prediction, Session } from "../schema";
import { DAY_MS, truncate } from "./util";
import { starterTypes } from "./planner";

/** Rotation: gym type done longest ago first (ties by starter order), then most frequent activities. */
export function rulesPredictions(sessions: Session[], now: number): Prediction[] {
  const lastGym = new Map<string, number>();
  for (const s of sessions) if (s.kind === "gym") lastGym.set(s.type, Math.max(lastGym.get(s.type) ?? 0, s.endedAt));
  const gymTypes = [...new Set([...starterTypes, ...lastGym.keys()])];
  const gym: Prediction[] = gymTypes
    .map((type, index) => ({ type, index, at: lastGym.get(type) ?? 0 }))
    .sort((a, b) => a.at - b.at || a.index - b.index)
    .map(({ type, at }) => ({
      kind: "gym" as const,
      type,
      reason: at === 0 ? "Not done yet" : truncate(`Last done ${Math.max(0, Math.floor((now - at) / DAY_MS))} days ago`, 80),
    }));

  const counts = new Map<string, number>();
  for (const s of sessions) if (s.kind === "activity") counts.set(s.type, (counts.get(s.type) ?? 0) + 1);
  const activity: Prediction[] = [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .slice(0, 3)
    .map(([type, n]) => ({ kind: "activity" as const, type, reason: `Done ${n} time${n === 1 ? "" : "s"}` }));
  return [...gym, ...activity];
}
