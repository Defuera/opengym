import { ConvexError } from "convex/values";
import { OWNER_USER_ID } from "./currentUser";

/**
 * The ONE place that turns the token of a request into a user (ADR-039). Every public query, mutation and action calls it first and uses the
 * returned user id for every read and write. When the login arrives, only the body of this function changes (it then looks the token up
 * in a session table, which is why it takes the context and is async). Its callers do not change.
 *
 * Today: the shared app token (env APP_TOKEN) is the owner. Nothing else is accepted.
 * `APP_EXTRA_TOKENS` is for TESTS ONLY: a JSON object {"<token>": "<userId>"} that maps more tokens to more users, so a test can act as a second
 * user. It is absent in every real deployment (do not set it there). A token that is also the app token stays the owner.
 *
 * `ctx` is not used yet; it is the first argument so the body can read the database later without a change at the callers.
 */
export async function requireUser(_ctx: object, token: string): Promise<string> {
  const expected = process.env.APP_TOKEN;
  if (expected && token === expected) return OWNER_USER_ID;
  const extra = extraTokens();
  const userId = extra[token];
  if (typeof userId === "string" && userId.length > 0 && token.length > 0) return userId;
  throw new ConvexError("unauthorized");
}

function extraTokens(): Record<string, unknown> {
  const raw = process.env.APP_EXTRA_TOKENS;
  if (!raw) return {};
  try {
    const parsed: unknown = JSON.parse(raw);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? (parsed as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}
