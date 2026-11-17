/** The title of a thread nobody named yet. */
export const NEW_CHAT_TITLE = "New chat";
export const THREAD_TITLE_MAX = 40;

/** Plain-code title from the first user message: first words, cut at a word boundary, max 40 characters, first letter upper case. */
export function titleFromMessage(text: string): string {
  const flat = text.replace(/\s+/g, " ").trim();
  if (!flat) return NEW_CHAT_TITLE;
  let cut = flat;
  if (flat.length > THREAD_TITLE_MAX) {
    const head = flat.slice(0, THREAD_TITLE_MAX + 1);
    const space = head.lastIndexOf(" ");
    cut = space > 0 ? head.slice(0, space) : flat.slice(0, THREAD_TITLE_MAX);
  }
  cut = cut.replace(/[\s.,;:!?-]+$/, "");
  if (!cut) return NEW_CHAT_TITLE;
  return cut.charAt(0).toUpperCase() + cut.slice(1);
}

/** Cleans an AI title: no quotes, no trailing period, one line. */
export function cleanAiTitle(raw: string): string {
  return raw.replace(/\s+/g, " ").replace(/^[\s"'“”‘’`]+|[\s"'“”‘’`.]+$/g, "");
}
