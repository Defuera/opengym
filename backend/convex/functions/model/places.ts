import type { Session } from "./schema";
import { activityKey } from "./sessionShape";

/**
 * The place of the newest session of an activity (ADR-021): the plain-code guess of where today's session is.
 * `sessions` is the live history, oldest first. Undefined when the activity has no session, or its newest session has no place.
 */
export function lastPlaceIdFor(sessions: Session[], activity: string): string | undefined {
  const k = activityKey(activity);
  for (let i = sessions.length - 1; i >= 0; i--) if (activityKey(sessions[i]!.type) === k) return sessions[i]!.placeId;
  return undefined;
}
