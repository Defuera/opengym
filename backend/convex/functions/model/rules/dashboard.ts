import { repEntries, topKg, totalMinutes, type Dashboard, type DashboardModule, type DashboardSpec, type Goal, type ModuleSpec, type Session } from "../schema";
import { stats } from "./stats";
import { DAY_MS, dayKey, fmtKg, whenLabel } from "./util";

export const MAX_MODULES = 10;

/** Fallback layout: sessions, active days, top set of most-trained exercise, goal progress per active goal, recent sessions. */
export function rulesSpec(goals: Goal[]): DashboardSpec {
  const modules: ModuleSpec[] = [
    { type: "stat", which: "sessions" },
    { type: "stat", which: "active_days" },
    { type: "stat", which: "top_set" },
    ...goals.filter((g) => g.status === "active").slice(0, 4).map((g): ModuleSpec => ({ type: "goal_progress", goalId: g.id })),
    { type: "recent_sessions", limit: 5 },
  ];
  return { source: "rules", modules: modules.slice(0, MAX_MODULES) };
}

function bestKg(sessions: Session[], exercise: string): number {
  const k = exercise.toLowerCase();
  let best = 0;
  for (const s of sessions) for (const e of s.exercises) if (e.name.toLowerCase() === k) best = Math.max(best, topKg(e));
  return best;
}

function goalModule(g: Goal, sessions: Session[], now: number): DashboardModule {
  if (g.kind === "strength" && g.exercise && g.targetKg) {
    const cur = bestKg(sessions, g.exercise);
    return {
      type: "goal_progress",
      goalId: g.id,
      title: g.title,
      current: `${fmtKg(cur)} kg`,
      target: `${fmtKg(g.targetKg)} kg`,
      fraction: Math.min(1, Math.max(0, cur / g.targetKg)),
    };
  }
  if (g.kind === "consistency" && g.sessionsPerWeek) {
    const n = sessions.filter((s) => s.endedAt >= now - 7 * DAY_MS).length;
    return {
      type: "goal_progress",
      goalId: g.id,
      title: g.title,
      current: String(n),
      target: `${g.sessionsPerWeek} / week`,
      fraction: Math.min(1, n / g.sessionsPerWeek),
    };
  }
  return { type: "goal_progress", goalId: g.id, title: g.title, current: g.status === "done" ? "Done" : "In progress", target: "", fraction: g.status === "done" ? 1 : null };
}

function sessionSubtitle(s: Session): string {
  const tag = s.focus ? `${s.focus} · ` : "";
  if (s.kind === "gym") {
    const sets = s.exercises.reduce((n, e) => n + repEntries(e).length, 0);
    const minutes = s.exercises.reduce((n, e) => n + totalMinutes(e), 0);
    return `${tag}${s.exercises.length} exercises, ${sets} sets${minutes > 0 ? `, ${fmtKg(minutes)} min` : ""}`;
  }
  return tag + [s.minutes !== undefined ? `${s.minutes} min` : null, s.distanceKm !== undefined ? `${fmtKg(s.distanceKm)} km` : null].filter(Boolean).join(", ") || "Activity";
}

/** Resolve a module spec to numbers computed from facts. Unknown goals are skipped. */
export function resolveDashboard(spec: DashboardSpec, sessions: Session[], goals: Goal[], days: 7 | 30, now: number): Dashboard {
  const st = stats(sessions, days, now);
  const from = now - days * DAY_MS;
  const modules: DashboardModule[] = [];
  for (const m of spec.modules) {
    switch (m.type) {
      case "stat": {
        if (m.which === "sessions") modules.push({ type: "stat", label: `Sessions, ${days} days`, value: String(st.sessions), highlighted: st.delta > 0 });
        else if (m.which === "active_days") modules.push({ type: "stat", label: "Active days", value: String(st.days), highlighted: false });
        else if (m.which === "sets") modules.push({ type: "stat", label: "Sets", value: String(st.sets), highlighted: false });
        else modules.push({ type: "stat", label: st.best ? `Top set, ${st.best}` : "Top set", value: st.top !== null ? `${fmtKg(st.top)} kg` : "–", highlighted: false });
        break;
      }
      case "goal_progress": {
        const g = goals.find((x) => x.id === m.goalId);
        if (g) modules.push(goalModule(g, sessions, now));
        break;
      }
      case "trend": {
        const exercise = m.exercise ?? st.best;
        if (!exercise) break;
        const k = exercise.toLowerCase();
        const points = sessions
          .filter((s) => s.endedAt >= from)
          .map((s) => ({ t: s.endedAt, value: Math.max(0, ...s.exercises.filter((e) => e.name.toLowerCase() === k).map(topKg)), has: s.exercises.some((e) => e.name.toLowerCase() === k) }))
          .filter((p) => p.has)
          .map(({ t, value }) => ({ t, value }));
        modules.push({ type: "trend", title: `${exercise}, top set`, unit: "kg", points });
        break;
      }
      case "consistency": {
        const active = new Set(sessions.map((s) => dayKey(s.endedAt)));
        const flags = Array.from({ length: days }, (_, i) => active.has(dayKey(now - (days - 1 - i) * DAY_MS)));
        modules.push({ type: "consistency", title: "Active days", days: flags });
        break;
      }
      case "recent_sessions": {
        const items = [...sessions].reverse().slice(0, m.limit ?? 5).map((s) => ({ title: s.type, subtitle: sessionSubtitle(s), trailing: whenLabel(s.endedAt, now) }));
        modules.push({ type: "recent_sessions", items });
        break;
      }
      case "note":
        modules.push({ type: "note", text: m.text });
        break;
    }
  }
  return { days, source: spec.source, modules: modules.slice(0, MAX_MODULES) };
}
