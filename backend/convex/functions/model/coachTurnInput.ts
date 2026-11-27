import { hasDone, type OpenExercise } from "./openSession";
import { type PlaceKnowledge, knowledgeOf } from "./placeKnowledge";
import { fmtKg } from "./rules/util";
import type { ContextItem, Goal, Limit } from "./schema";

/**
 * The part of a coach turn's input that is about the screen the person is on (ADR-032). Pure: jobs/coachTurn:input reads the rows.
 * The rest (history, log, goals, limits, notes, entries, files) comes from the chat input and model/coachContext.ts, as in a chat reply.
 */

export interface OpenRow {
  id: string;
  type: string;
  focus?: string;
  planNote?: string;
  placeId?: string;
  exercises: OpenExercise[];
}

export interface PlaceRow {
  placeId: string;
  name: string;
  text: string;
  knowledgeState?: PlaceKnowledge;
}

const setLine = (e: OpenExercise) => (s: OpenExercise["sets"][number]) =>
  `${e.measure === "time" ? `${s.minutes ?? 0} min${s.distanceKm !== undefined ? ` ${s.distanceKm} km` : ""}` : `${s.reps ?? 0}x${fmtKg(s.kg ?? 0)}${s.max ? " max" : ""}`}${s.done ? " done" : ""}`;

/** One exercise of the open session as the coach reads it. `personsWork`: a done set or a comment; no function may change it. */
export function exerciseForPrompt(e: OpenExercise) {
  return {
    id: e.id,
    name: e.name,
    ...(e.measure ? { measure: e.measure } : {}),
    sets: e.sets.map(setLine(e)),
    ...(e.note ? { coachNote: e.note } : {}),
    ...(e.comment ? { commentFromThePerson: e.comment } : {}),
    ...(e.commentFileIds?.length ? { commentPhotos: e.commentFileIds.length } : {}),
    personsWork: hasDone(e),
  };
}

/** Every place with its text and knowledge state, and which one is the session's place. */
export function placesForTurn(places: PlaceRow[], sessionPlaceId?: string) {
  return places.map((p) => ({ placeId: p.placeId, name: p.name, equipment: p.text, knowledge: knowledgeOf(p), ...(p.placeId === sessionPlaceId ? { isSessionPlace: true } : {}) }));
}

/** The screen part of the turn: the open session (server copy), the exercise in view, the session's place, all places. */
export function turnScreen(o: { screen?: string; row: OpenRow | null; exerciseId?: string; places: PlaceRow[]; placeId?: string }) {
  const row = o.row;
  const current = row && o.exerciseId ? row.exercises.find((e) => e.id === o.exerciseId) : undefined;
  const place = row?.placeId ? o.places.find((p) => p.placeId === row.placeId) : undefined;
  const asked = o.placeId ? o.places.find((p) => p.placeId === o.placeId) : undefined;
  return {
    screen: o.screen ?? "chat",
    openSession: row
      ? { id: row.id, activity: row.type, ...(row.focus ? { focus: row.focus } : {}), ...(row.planNote ? { planNote: row.planNote } : {}), place: place ? place.name : null, exercises: row.exercises.map(exerciseForPrompt) }
      : null,
    ...(current ? { currentExercise: { id: current.id, name: current.name } } : {}),
    ...(place ? { sessionPlace: { placeId: place.placeId, name: place.name } } : {}),
    ...(asked && asked !== place ? { placeInView: { placeId: asked.placeId, name: asked.name } } : {}),
    places: placesForTurn(o.places, row?.placeId),
  };
}

const EDITABLE_MAX = 30;

/**
 * What the coach may change by a draft (ADR-032, step D): the person's goals, limits and notes with their ids, and the one in view.
 * A limit shows the kind and text of its rules only, never an exercise list or a record (ADR-015). Pure.
 */
export function editablesForTurn(o: { goals: Goal[]; limits: Limit[]; notes: ContextItem[]; goalId?: string; limitId?: string; noteId?: string; part?: string }) {
  const goals = o.goals.filter((g) => g.status === "active").slice(0, EDITABLE_MAX).map((g) => ({ id: g.id, title: g.title, kind: g.kind, ...(g.exercise ? { exercise: g.exercise } : {}), ...(g.targetKg !== undefined ? { targetKg: g.targetKg } : {}), ...(g.sessionsPerWeek !== undefined ? { sessionsPerWeek: g.sessionsPerWeek } : {}) }));
  const limits = o.limits.slice(0, EDITABLE_MAX).map((l) => ({ id: l.limitId, part: l.part, title: l.title, status: l.status, ...(l.since ? { since: l.since } : {}), rules: l.rules.map((r) => ({ kind: r.kind, text: r.text })) }));
  const notes = o.notes.slice(0, EDITABLE_MAX).map((n) => ({ id: n.id, topic: n.topic, text: n.text, active: n.active }));
  return {
    ...(goals.length > 0 ? { goalsYouMayChange: goals } : {}),
    ...(limits.length > 0 ? { limitsYouMayChange: limits } : {}),
    ...(notes.length > 0 ? { notesYouMayChange: notes } : {}),
    ...(o.goalId && goals.some((g) => g.id === o.goalId) ? { goalInView: o.goalId } : {}),
    ...(o.limitId && limits.some((l) => l.id === o.limitId) ? { limitInView: o.limitId } : {}),
    ...(o.noteId && notes.some((n) => n.id === o.noteId) ? { noteInView: o.noteId } : {}),
    ...(o.part ? { bodyPartInView: o.part } : {}),
  };
}
