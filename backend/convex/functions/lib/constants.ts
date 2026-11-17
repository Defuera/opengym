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
