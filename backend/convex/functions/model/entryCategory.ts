/**
 * The category of a log entry (ADR-031): a short label the AI picks, with code keeping the set tidy. Pure.
 * Old rows hold one of "meal", "training", "body", "goal", "other"; they stay readable (see `categoryLabel`).
 */

export const CATEGORY_MAX = 24;
/** What the AI is told when the person has no category yet, and the fallback of the plain-note draft. "other" is the old "no label". */
export const NO_CATEGORY = "other";
const LEGACY: Record<string, string> = { meal: "Meal", training: "Training", body: "Body", goal: "Goal" };

/** The label as shown: the old values map to Title case; "other" (the old "none of these") and an empty value have no label. */
export function categoryLabel(raw: string | undefined): string | null {
  const s = (raw ?? "").replace(/\s+/g, " ").trim();
  if (!s || s.toLowerCase() === NO_CATEGORY) return null;
  return LEGACY[s.toLowerCase()] ?? s;
}

/** The key two spellings of one category share. */
export const categoryKey = (label: string): string => label.replace(/\s+/g, " ").trim().toLowerCase();

const titleCase = (s: string): string => s.toLowerCase().replace(/(^|[\s-])(\p{L})/gu, (_m, a: string, b: string) => `${a}${b.toUpperCase()}`);

/**
 * Makes the AI's label a category: trims, collapses spaces, cuts at 24 characters, matches a known label without regard to case (the known
 * spelling wins), else Title case. An empty label gives NO_CATEGORY.
 */
export function normaliseCategory(raw: string, known: readonly string[] = []): string {
  const s = raw.replace(/\s+/g, " ").trim().slice(0, CATEGORY_MAX).trim();
  if (!s) return NO_CATEGORY;
  const key = categoryKey(s);
  const hit = known.find((k) => categoryKey(k) === key);
  return hit ?? LEGACY[key] ?? (key === NO_CATEGORY ? NO_CATEGORY : titleCase(s));
}

/** The categories the person's entries use, most used first (ties: the first seen, so newest first). Old values count as their new label. */
export function usedCategories(kinds: readonly (string | undefined)[], max = 20): string[] {
  const count = new Map<string, { label: string; n: number }>();
  for (const k of kinds) {
    const label = categoryLabel(k);
    if (!label) continue;
    const key = categoryKey(label);
    const c = count.get(key);
    if (c) c.n += 1;
    else count.set(key, { label, n: 1 });
  }
  return [...count.values()].sort((a, b) => b.n - a.n).slice(0, max).map((c) => c.label);
}
