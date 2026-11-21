import type { Session } from "../schema";
import { activityKey } from "../sessionShape";

type Kind = Session["kind"];

/** One activity of the log: sessions of one kind with the same name key. */
export interface LoggedActivity {
  kind: Kind;
  key: string;
  /** The most recent spelling in the log. */
  name: string;
  count: number;
  /** Sessions in the last 60 days (for ranking). */
  recent: number;
  /** endedAt of the last session. */
  last: number;
}

export const RECENT_DAYS = 60;
const DAY = 86_400_000;

/** The activities the log holds. The vocabulary comes from here and nowhere else (ADR-016). Order: most used recently first. */
export function loggedActivities(sessions: Session[], now: number = Date.now()): LoggedActivity[] {
  const by = new Map<string, LoggedActivity>();
  for (const s of sessions) {
    const key = activityKey(s.type);
    if (key === "") continue;
    const id = `${s.kind}:${key}`;
    const a = by.get(id) ?? { kind: s.kind, key, name: s.type.trim(), count: 0, recent: 0, last: 0 };
    a.count++;
    if (s.endedAt >= now - RECENT_DAYS * DAY) a.recent++;
    if (s.endedAt >= a.last) {
      a.last = s.endedAt;
      a.name = s.type.trim();
    }
    by.set(id, a);
  }
  return [...by.values()].sort((a, b) => b.recent - a.recent || b.count - a.count || b.last - a.last || a.name.localeCompare(b.name));
}

/** The log's spelling of an activity (most recent), or null when the log has no such name. */
export function loggedName(sessions: Session[], name: string, kind?: Kind): string | null {
  const key = activityKey(name);
  let best: Session | null = null;
  for (const s of sessions) if (activityKey(s.type) === key && (kind === undefined || s.kind === kind) && (!best || s.endedAt >= best.endedAt)) best = s;
  return best ? best.type.trim() : null;
}

const isSetBasedOf = (s: Session, key: string) => s.kind === "gym" && activityKey(s.type) === key;

/** Foci in the log for one set-based activity (the log's most recent spelling), done longest ago first. This is the order of what is due. */
export function fociByDue(sessions: Session[], activity: string): string[] {
  const key = activityKey(activity);
  const last = new Map<string, { at: number; name: string }>();
  for (const s of sessions) {
    if (!isSetBasedOf(s, key) || !s.focus) continue;
    const k = activityKey(s.focus);
    const cur = last.get(k);
    if (!cur || s.endedAt >= cur.at) last.set(k, { at: s.endedAt, name: s.focus.trim() });
  }
  return [...last.values()].sort((a, b) => a.at - b.at || a.name.localeCompare(b.name)).map((x) => x.name);
}

/**
 * Every focus the log holds for one set-based activity, with how often it was logged. Most used first, then most recent.
 * The name is the log's most recent spelling. The coach reads this list to reuse a focus name and not invent a new one.
 */
export function fociByUse(sessions: Session[], activity: string): { focus: string; timesLogged: number }[] {
  const key = activityKey(activity);
  const by = new Map<string, { focus: string; timesLogged: number; last: number }>();
  for (const s of sessions) {
    if (!isSetBasedOf(s, key) || !s.focus?.trim()) continue;
    const k = activityKey(s.focus);
    const cur = by.get(k) ?? { focus: s.focus.trim(), timesLogged: 0, last: 0 };
    cur.timesLogged++;
    if (s.endedAt >= cur.last) Object.assign(cur, { last: s.endedAt, focus: s.focus.trim() });
    by.set(k, cur);
  }
  return [...by.values()].sort((a, b) => b.timesLogged - a.timesLogged || b.last - a.last).map(({ focus, timesLogged }) => ({ focus, timesLogged }));
}

/** The last session with sets of an activity (and of a focus, when one is given), or null. */
export function lastOfActivity(sessions: Session[], activity: string, focus?: string): Session | null {
  const key = activityKey(activity);
  const fk = focus === undefined ? null : activityKey(focus);
  for (let i = sessions.length - 1; i >= 0; i--) {
    const s = sessions[i]!;
    if (isSetBasedOf(s, key) && (fk === null || activityKey(s.focus ?? "") === fk)) return s;
  }
  return null;
}
