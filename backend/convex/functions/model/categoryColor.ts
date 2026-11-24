/**
 * The colour of a log category (ADR-031). The AI picks it for a new category, with this palette in its prompt as guidance only. Code
 * checks only that the value is a hex colour. Pure.
 */

/** Example colours for the prompt: mid-dark, saturated, readable on a white card, none of them black. Guidance for the AI, not a limit. */
export const REFERENCE_PALETTE = ["#2B4FD6", "#1F7A45", "#B45309", "#6D35C9", "#C0392B", "#0F766E", "#BE185D", "#8A6A00"] as const;

/** "#RRGGBB" in upper case, or null when the value is not a hex colour of that form. */
export function parseColor(raw: string | null | undefined): string | null {
  const s = (raw ?? "").trim();
  return /^#[0-9a-fA-F]{6}$/.test(s) ? s.toUpperCase() : null;
}

/** The colour when the AI gave none: the first reference colour not in use, else the palette in turn. */
export function fallbackColor(inUse: readonly string[]): string {
  const used = new Set(inUse.map((c) => c.toUpperCase()));
  return REFERENCE_PALETTE.find((c) => !used.has(c)) ?? REFERENCE_PALETTE[inUse.length % REFERENCE_PALETTE.length]!;
}

/** The prompt text about colour, shared by read_entry and the log chat. `where` names the field that holds the category. */
export const COLOR_RULE = `color: only for a NEW category (one that is not in categoriesInUse), as "#RRGGBB". Pick a colour that fits the meaning of the category and is clearly different from the colours of categoriesInUse. It must be mid-dark and saturated, readable as text and as a border on a white card, and never black or near black. Example colours, as guidance only (pick one of them or something near them): ${REFERENCE_PALETTE.join(", ")}. For a category that is in categoriesInUse, leave color out: its colour is fixed.`;
