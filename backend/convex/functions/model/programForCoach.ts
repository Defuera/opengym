import { programNow } from "./program";
import type { PlanExercise, ProgramPhase, Session } from "./schema";

/** The fields of a stored program that the coach and the link need. */
export interface ProgramForCoach {
  programId: string;
  title: string;
  purpose: string;
  status: "active" | "paused" | "done";
  startsOn: string;
  endsOn: string;
  week: string[];
  phases: ProgramPhase[];
  rules: string[];
  tests: (string | { text: string })[];
}

/** One written exercise as a short line: "Leg Press: 12x20, 12x30 (note)". */
const line = (e: PlanExercise): string =>
  `${e.name}: ${e.sets.map((x) => ("minutes" in x ? `${x.minutes} min` : `${x.reps}x${x.kg}${x.max ? " max" : ""}`)).join(", ")}${e.note ? ` (${e.note})` : ""}`;

/** The slots of this program week that live sessions have done, as "week:slot". */
const doneSlots = (programId: string, sessions: Session[]) => new Set(sessions.filter((s) => s.programId === programId).map((s) => `${s.programWeek}:${s.programSlot}`));

/**
 * What the coach reads of the programs the person follows (ADR-030): only active programs that run on `today` (a local "YYYY-MM-DD").
 * Each has the week, the phase of that week, the slots of the week with done or not, and the sessions as written for the phase.
 * Plain code, no AI. `sessions` is the FULL history.
 */
export function programsForCoach(programs: ProgramForCoach[], sessions: Session[], today: string) {
  return programs
    .filter((p) => p.status === "active")
    .map((p) => {
      const done = doneSlots(p.programId, sessions);
      const now = programNow(p, today, (week, slot) => done.has(`${week}:${slot}`), (s) => s.exercises);
      const phase = p.phases[now.phaseIndex];
      if (now.state !== "running" || !phase) return null;
      return {
        programId: p.programId,
        title: p.title,
        purpose: p.purpose,
        startsOn: p.startsOn,
        endsOn: p.endsOn,
        week: `${now.week} of ${now.weeks}`,
        phase: { title: phase.title, note: phase.note },
        slotsThisWeek: now.slots.map((s) => ({ slot: s.slot, key: s.key, title: s.title, done: s.done })),
        sessionsAsWritten: phase.sessions.map((s) => ({ key: s.key, title: s.title, activity: s.activity, exercises: s.exercises.map(line), ...(s.note ? { note: s.note } : {}) })),
        rules: p.rules,
        tests: p.tests.map((t) => (typeof t === "string" ? t : t.text)),
      };
    })
    .filter((p) => p !== null);
}

/**
 * The program link of a proposed session: the coach names the program and the session key, code finds the place. The slot is the first
 * slot of this week with that key that no session has done. Null when the program is not active or not running, the key is not in this
 * week, or every slot with that key is done (then the session is a plain one).
 */
export function programLinkFor(p: ProgramForCoach | null, key: string, sessions: Session[], today: string): { programId: string; week: number; slot: number; key: string } | null {
  if (!p || p.status !== "active") return null;
  const done = doneSlots(p.programId, sessions);
  const now = programNow(p, today, (week, slot) => done.has(`${week}:${slot}`), (s) => s.exercises);
  if (now.state !== "running") return null;
  const open = now.slots.find((s) => s.key === key && !s.done);
  return open ? { programId: p.programId, week: now.week, slot: open.slot, key } : null;
}
