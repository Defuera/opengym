import type { Pattern } from "../types";

/** Lower case, every run of other characters becomes one space: "Pull-up  bar!" -> "pull up bar". */
export const norm = (s: string): string => s.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();

const escape = (s: string): string => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** A keyword matches as a whole word or phrase (a plural "s" or "es" is fine) in the normalised text. A { re } matches the raw text. */
export function matches(text: string, p: Pattern): boolean {
  // Curly quotes count as straight ones, so a pattern with "can't" also matches the typographic form.
  if (typeof p !== "string") return new RegExp(p.re, p.flags ?? "i").test(text.replace(/[\u2018\u2019]/g, "'").replace(/[\u201C\u201D]/g, '"'));
  const k = norm(p);
  return k !== "" && new RegExp(`(?:^| )${escape(k)}(?:s|es)?(?= |$)`).test(norm(text));
}

/** The patterns of the list that match the text. */
export const hits = (text: string, list: Pattern[]): Pattern[] => list.filter((p) => matches(text, p));

export const show = (p: Pattern): string => (typeof p === "string" ? `"${p}"` : `/${p.re}/${p.flags ?? "i"}`);

/** A short excerpt of a text for a report line. */
export const excerpt = (s: string, n = 160): string => (s.length <= n ? s : `${s.slice(0, n - 1)}…`);

const words = (s: string): string[] => norm(s).split(" ").filter(Boolean);

/** Share (0..1) of the word 4-grams of `a` that also stand in `b`. 0 when `a` is shorter than four words. */
export function overlap(a: string, b: string, n = 4): number {
  const wa = words(a);
  const wb = words(b);
  if (wa.length < n) return 0;
  const grams = (w: string[]) => new Set(w.slice(0, Math.max(0, w.length - n + 1)).map((_, i) => w.slice(i, i + n).join(" ")));
  const ga = grams(wa);
  const gb = grams(wb);
  let shared = 0;
  for (const g of ga) if (gb.has(g)) shared++;
  return ga.size === 0 ? 0 : shared / ga.size;
}
