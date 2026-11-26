/**
 * The ONE place that reads the time zone variable (ADR-039). The zone of a user is `users.timezone` when it is set, else the deployment's
 * APP_TIMEZONE (an IANA name), else UTC. Pure: code with a database context gets the user row through `lib/timezoneDb:userTimezone`.
 * Day and clock functions take the zone as an optional last argument and call this with nothing (the deployment zone) when they get none.
 */
export function timezoneOf(user?: { timezone?: string } | null): string {
  return user?.timezone || process.env.APP_TIMEZONE || "UTC";
}
