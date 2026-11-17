import type { Prediction, Session } from "../schema";
import { MAX_PREDICTIONS, activityKey, normalizePredictions } from "../sessionShape";
import { type LoggedActivity, fociByDue, loggedActivities, loggedName } from "./foci";
import { DAY_MS, truncate } from "./util";

export function agoLabel(at: number, now: number): string {
  const d = Math.max(0, Math.floor((now - at) / DAY_MS));
  return d === 0 ? "today" : d === 1 ? "yesterday" : `${d} days ago`;
}

const lastAt = (sessions: Session[], a: LoggedActivity, focus?: string): number => {
  let at = 0;
  for (const s of sessions) if (s.kind === a.kind && activityKey(s.type) === a.key && (focus === undefined || activityKey(s.focus ?? "") === activityKey(focus))) at = Math.max(at, s.endedAt);
  return at;
};

/**
 * What the user will most likely do next (ADR-016). Nothing is invented: every activity and focus comes from the log,
 * so an empty log gives an empty list. Any activity can be ranked, with sets or not.
 * Activities are ranked by sessions in the last 60 days, then by all sessions, then by recency.
 * A session with sets gets the focus done longest ago; a second item of the same activity is added only when the log has a second focus.
 * The first item of every activity comes first, second items follow. At most 2 items per activity, 6 in total.
 */
export function rulesPredictions(sessions: Session[], now: number): Prediction[] {
  const ranked = loggedActivities(sessions, now);
  const firsts: Prediction[] = [];
  const seconds: Prediction[] = [];
  for (const a of ranked) {
    if (a.kind === "gym") {
      const foci = fociByDue(sessions, a.name);
      const last = [...sessions].reverse().find((s) => s.kind === "gym" && activityKey(s.type) === a.key)!;
      const reason = `Last ${(last.focus ?? a.name).toLowerCase()} session was ${agoLabel(last.endedAt, now)}`;
      firsts.push({ kind: "gym", type: a.name, ...(foci[0] ? { focus: foci[0] } : {}), reason: truncate(reason, 80) });
      if (foci[1]) seconds.push({ kind: "gym", type: a.name, focus: foci[1], reason: truncate(`Last ${foci[1].toLowerCase()} session was ${agoLabel(lastAt(sessions, a, foci[1]), now)}`, 80) });
    } else {
      const focus = advisedActivityFocus(sessions, a.name);
      firsts.push({ kind: "activity", type: a.name, ...(focus ? { focus } : {}), reason: `Done ${a.count} time${a.count === 1 ? "" : "s"}` });
    }
  }
  return [...firsts, ...seconds].slice(0, MAX_PREDICTIONS);
}

/** The session type of this activity done longest ago, when the log has any with a type. Otherwise none. */
export function advisedActivityFocus(sessions: Session[], type: string): string | undefined {
  const key = activityKey(type);
  const last = new Map<string, { at: number; name: string }>();
  for (const s of sessions) {
    if (s.kind !== "activity" || activityKey(s.type) !== key || !s.focus) continue;
    const k = activityKey(s.focus);
    const cur = last.get(k);
    if (!cur || s.endedAt >= cur.at) last.set(k, { at: s.endedAt, name: s.focus.trim() });
  }
  return [...last.values()].sort((a, b) => a.at - b.at)[0]?.name;
}

/**
 * The hard check after the model (ADR-004), in code: names are checked against the log by `activityKey`.
 * An item whose activity is not in the log (with that kind) is dropped. A kept item gets the log's spelling.
 * For a session with sets, a focus that is not one of that activity's logged foci is replaced by the focus due, or left out when the log has none.
 * Then the list is normalised (legacy shape, no repeats, at most 2 per activity, 6 in total).
 */
export function validatePredictions(items: Prediction[], sessions: Session[]): Prediction[] {
  const checked: Prediction[] = [];
  for (const p of normalizePredictions(items)) {
    const name = loggedName(sessions, p.type, p.kind);
    if (name === null) continue;
    if (p.kind === "gym") {
      const foci = fociByDue(sessions, name);
      const fk = p.focus ? activityKey(p.focus) : "";
      const hit = foci.find((f) => activityKey(f) === fk);
      const focus = hit ?? foci[0];
      checked.push({ kind: "gym", type: name, ...(focus ? { focus } : {}), reason: p.reason });
    } else {
      checked.push({ ...p, type: name, ...(p.focus ? { focus: p.focus.slice(0, 40) } : {}) });
    }
  }
  return normalizePredictions(checked);
}
