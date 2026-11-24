import { hasDone, type OpenExercise } from "./openSession";
import { type PlaceKnowledge, knowledgeOf } from "./placeKnowledge";
import { fmtKg } from "./rules/util";

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
