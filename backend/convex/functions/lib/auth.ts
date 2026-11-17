import { ConvexError } from "convex/values";

/**
 * Interim single-user gate: every public function takes the shared app token.
 * Replace with real user accounts before a second person uses the app.
 */
export function requireToken(token: string) {
  const expected = process.env.APP_TOKEN;
  if (!expected || token !== expected) throw new ConvexError("unauthorized");
}
