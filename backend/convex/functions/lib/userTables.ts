/**
 * The tables that hold a person's data (ADR-039): every row has a `userId`. Used by the migration (jobs/migrations), the report and the tests.
 * NOT in the list: `users` (the people), `exerciseArt` (shared by all users, a catalogue of drawings with no personal data).
 */
export const PER_USER_TABLES = [
  "sessions", "goals", "context", "entries", "entryCategories", "trackerDays", "trackerWorkouts", "places", "placeChanges", "programs", "proposals",
  "limits", "records", "checkins", "imports", "threads", "messages", "files", "plans", "predictions", "dashboards", "reviews", "startRequests",
  "aiCalls", "aiUsage", "openSession", "settings", "rebuilds",
] as const;
export type PerUserTable = (typeof PER_USER_TABLES)[number];

/** Rows read per page of the migration and of the report. Tables with big rows get a smaller page (a mutation reads at most 16 MiB). */
export const PAGE_SIZE: Record<PerUserTable, number> = Object.fromEntries(PER_USER_TABLES.map((t) => [t, 100])) as Record<PerUserTable, number>;
PAGE_SIZE.aiCalls = 20;
PAGE_SIZE.messages = 50;
PAGE_SIZE.proposals = 50;
PAGE_SIZE.programs = 50;
PAGE_SIZE.sessions = 50;
