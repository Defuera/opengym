import type { KnownActivity } from "./ai/jobs/shared";
import { type StartProposal } from "./schema";
import { activityKey } from "./sessionShape";

/** First letter upper case, the text before the first comma, at most 40 characters. The same rule the app uses offline. */
export function nameFromText(text: string): string {
  const first = (text.split(",")[0] ?? "").trim() || text.trim();
  const cut = first.slice(0, 40).trim();
  return cut === "" ? "Gym" : cut.charAt(0).toUpperCase() + cut.slice(1);
}

/** Plain-code fallback of a start request: a session with sets under the given name, else the name from the text (a known spelling when the log has one), with an empty plan. */
export function fallbackProposal(i: { text: string; name?: string | null; known: KnownActivity[] }): StartProposal {
  const name = i.name?.trim() ? i.name.trim().slice(0, 40) : nameFromText(i.text);
  const known = i.known.find((a) => activityKey(a.type) === activityKey(name));
  return { kind: "gym", type: known?.type ?? name, plan: { rationale: "Empty session. Add what you do.", exercises: [] } };
}
