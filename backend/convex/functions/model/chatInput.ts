/** Bounds on what the coach reads in a chat reply (ADR-012). The model never gets the full history. */
export const CHAT_HISTORY_MESSAGES = 20;
export const CHAT_OTHER_THREADS = 8;
export const CHAT_RECENT_SESSIONS = 10;
export const CHAT_GOALS = 30;
export const CHAT_CONTEXT_ITEMS = 40;
/** Titles/texts sent to extract_from_chat so it does not repeat itself. Dedupe against the whole database happens in code. */
export const CHAT_KNOWN_ITEMS = 50;
