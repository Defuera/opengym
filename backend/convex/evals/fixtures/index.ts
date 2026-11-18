import type { EvalPlace, Persona } from "../types";
import { activityKey } from "../../functions/model/sessionShape";
import { jonas } from "./jonas";
import { mara } from "./mara";
import { nia } from "./nia";

export { NOW } from "./build";
export const PERSONAS: Record<string, Persona> = { mara, jonas, nia };

export function persona(id: string): Persona {
  const p = PERSONAS[id];
  if (!p) throw new Error(`unknown persona "${id}"`);
  return p;
}

/** A place of a persona by its name (any case). Throws on an unknown name: a case that names it is wrong. */
export function placeOf(p: Persona, name: string): EvalPlace {
  const k = activityKey(name);
  const place = p.places.find((x) => activityKey(x.name) === k);
  if (!place) throw new Error(`persona ${p.id} has no place "${name}"`);
  return place;
}
