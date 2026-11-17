import type { Prediction, Session } from "../schema";
import { GYM_TYPE } from "../schema/common";
import { gymFociByDue } from "./foci";
import { DAY_MS, truncate } from "./util";

export function agoLabel(at: number, now: number): string {
  const d = Math.max(0, Math.floor((now - at) / DAY_MS));
  return d === 0 ? "today" : d === 1 ? "yesterday" : `${d} days ago`;
}

/**
 * Activities are ranked, not gym flavours (ADR-013). Gym appears once, with the advised focus:
 * the gym focus done longest ago. The reason names the last gym session, e.g. "last legs session was 2 days ago".
 * Then the most frequent other activities, each with an advised session type when the log has one.
 */
export function rulesPredictions(sessions: Session[], now: number): Prediction[] {
  const gymSessions = sessions.filter((s) => s.kind === "gym");
  const lastGym = gymSessions.reduce<Session | null>((a, s) => (!a || s.endedAt >= a.endedAt ? s : a), null);
  const advised = gymFociByDue(sessions)[0];
  const gymReason = !lastGym ? "No gym session logged yet" : lastGym.focus ? `Last ${lastGym.focus.toLowerCase()} session was ${agoLabel(lastGym.endedAt, now)}` : `Last gym session was ${agoLabel(lastGym.endedAt, now)}`;
  const gym: Prediction = { kind: "gym", type: GYM_TYPE, ...(advised ? { focus: advised } : {}), reason: truncate(gymReason, 80) };

  const counts = new Map<string, number>();
  for (const s of sessions) if (s.kind === "activity") counts.set(s.type, (counts.get(s.type) ?? 0) + 1);
  const activity: Prediction[] = [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .slice(0, 3)
    .map(([type, n]) => {
      const focus = advisedActivityFocus(sessions, type);
      return { kind: "activity" as const, type, ...(focus ? { focus } : {}), reason: `Done ${n} time${n === 1 ? "" : "s"}` };
    });
  return [gym, ...activity];
}

/** The session type of this activity done longest ago, when the log has any with a type. Otherwise none. */
export function advisedActivityFocus(sessions: Session[], type: string): string | undefined {
  const last = new Map<string, number>();
  for (const s of sessions) if (s.kind === "activity" && s.type === type && s.focus) last.set(s.focus, Math.max(last.get(s.focus) ?? 0, s.endedAt));
  return [...last.entries()].sort((a, b) => a[1] - b[1])[0]?.[0];
}

/** The focus the app should pre-select for a gym session: from the prediction list, else from the rotation. */
export function advisedGymFocus(predictions: Prediction[], sessions: Session[]): string {
  return predictions.find((p) => p.kind === "gym")?.focus ?? gymFociByDue(sessions)[0]!;
}
