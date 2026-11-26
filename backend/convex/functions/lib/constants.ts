/** Rebuild debounce (see facts-changed.ts). */
export const REBUILD_DEBOUNCE_MS = 5_000;
/** A steady stream of writes cannot delay a rebuild longer than this. */
export const REBUILD_MAX_WAIT_MS = 30_000;

/** Structured import: up to this many documents are written in the command itself; more go in batches. */
export const IMPORT_INLINE_MAX = 250;
export const IMPORT_BATCH_SIZE = 250;
/** Documents deleted per mutation when an import is removed. */
export const IMPORT_DELETE_BATCH = 1_000;

/** AI import of files: pause between starting two units, so a long PDF does not fire all its calls at once. */
export const IMPORT_UNIT_STAGGER_MS = 1_000;

/** A start request (a typed "Start session" text) is removed after this long. */
export const START_REQUEST_TTL_MS = 86_400_000;
/** Longest text of a start request. */
export const START_REQUEST_MAX_TEXT = 2000;
export const START_REQUEST_MAX_NAME = 40;
/** Feedback on a proposed session: longest text, and how many rounds a request keeps (oldest dropped). */
export const START_FEEDBACK_MAX = 1000;
export const START_FEEDBACK_KEEP = 5;
/** Old start requests removed per command call. */
export const START_REQUEST_PURGE_BATCH = 50;

/** A session or note marked as deleted is erased for good after this long (ADR-020). */
export const DELETE_AFTER_MS = 72 * 3_600_000;
/** Rows erased per purge pass; a full pass schedules the next one. */
export const PURGE_BATCH = 50;

/** Exercise art: at most this many new or retried art rows in the last 24 hours (names over the cap are skipped silently). */
export const EXERCISE_ART_DAILY_MAX = 40;
/** A failed art row is tried again by the next request when it is older than this. */
export const EXERCISE_ART_RETRY_MS = 86_400_000;

/** A proposal (a coach proposal the person must agree to) is removed after this long, whatever its status. */
export const PROPOSAL_TTL_MS = 7 * 86_400_000;
/** Old proposals removed per command call. */
export const PROPOSAL_PURGE_BATCH = 50;
/** Longest ask text of a proposal; the longest feedback; how many feedback rounds a rebuild keeps (oldest dropped). */
export const PROPOSAL_TEXT_MAX = 8000;
export const PROPOSAL_FEEDBACK_MAX = 1000;
export const PROPOSAL_FEEDBACK_KEEP = 5;
/** `queries/proposals:open` returns at most this many. */
export const PROPOSAL_OPEN_MAX = 5;
/** The most proposals queries/proposals:forThread returns. */
export const PROPOSAL_FOR_THREAD_MAX = 50;
/** A program lasts at most this many weeks. */
export const PROGRAM_MAX_WEEKS = 26;
/** The AI budget to write one program (a long pasted program can take two minutes). */
export const PROGRAM_BUILD_BUDGET_MS = 300_000;

/** A stored AI call (what was sent to the model and what came back) is erased after this long (ADR-027). */
export const AI_CALL_KEEP_MS = 90 * 86_400_000;
/** Longest text kept per field of a stored AI call; longer text is cut. */
export const AI_CALL_TEXT_MAX = 200_000;

/** The most `aiUsage` rows one summary reads (ADR-038). A larger range answers with `truncated: true`. */
export const USAGE_SUMMARY_MAX_ROWS = 8000;
/** The longest range one summary accepts, and the range it reads when `from` is absent. */
export const USAGE_SUMMARY_MAX_DAYS = 366;
export const USAGE_SUMMARY_DEFAULT_DAYS = 30;
