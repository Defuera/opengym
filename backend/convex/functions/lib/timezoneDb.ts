import type { DatabaseReader } from "../_generated/server";
import { timezoneOf } from "../model/timezone";

/** The time zone of a user (ADR-039): `users.timezone` when the user has a row with one, else the deployment's APP_TIMEZONE, else UTC. */
export async function userTimezone(ctx: { db: DatabaseReader }, userId: string): Promise<string> {
  const user = await ctx.db.query("users").withIndex("by_userId", (q) => q.eq("userId", userId)).unique();
  return timezoneOf(user);
}
