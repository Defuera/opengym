import type { Session } from "../schema";
import { DAY_MS, dayKey } from "./util";

export interface StatsResult {
  sessions: number;
  delta: number;
  days: number;
  sets: number;
  best: string | null;
  top: number | null;
}

/** Window stats over [now - days, now], delta against the window before. Port of planner.dart stats(). */
export function stats(sessions: Session[], days: number, now: number): StatsResult {
  const from = now - days * DAY_MS;
  const prev = from - days * DAY_MS;
  let cur = 0;
  let before = 0;
  let sets = 0;
  const dayKeys = new Set<string>();
  const count = new Map<string, number>();
  const top = new Map<string, number>();
  for (const s of sessions) {
    if (s.endedAt >= from) {
      cur++;
      dayKeys.add(dayKey(s.endedAt));
      for (const e of s.exercises) {
        for (const x of e.sets) {
          sets++;
          count.set(e.name, (count.get(e.name) ?? 0) + 1);
          top.set(e.name, Math.max(top.get(e.name) ?? 0, x.kg));
        }
      }
    } else if (s.endedAt >= prev) {
      before++;
    }
  }
  let best: string | null = null;
  let bestCount = 0;
  for (const [name, n] of count) {
    if (n > bestCount) {
      best = name;
      bestCount = n;
    }
  }
  return { sessions: cur, delta: cur - before, days: dayKeys.size, sets, best, top: best ? (top.get(best) ?? 0) : null };
}
