import type { Persona } from "../types";

/** A new user: nothing logged, nothing known. */
export const nia: Persona = {
  id: "nia",
  about: "New user. No sessions, no goals, no limits, no notes. One place with no text.",
  places: [{ placeId: "pl-nia-home", name: "Home", text: "", has: [], lacks: [] }],
  sessions: [],
  goals: [],
  limits: [],
  context: [],
  entries: [],
};
