/**
 * The id of the user a write belongs to. Every write to `aiUsage` gets its `userId` from here, and from nowhere else (ADR-038).
 *
 * Today the app has one user, so this returns the constant "owner". The multi-user phase replaces the BODY of this function with the real
 * lookup (the signed-in user of the request, or the user id a job was started for); its callers do not change. Its signature will then
 * probably gain a context or a job argument. Do not thread a user id through other tables before that phase.
 */
export const OWNER_USER_ID = "owner";

export function currentUserId(): string {
  return OWNER_USER_ID;
}
