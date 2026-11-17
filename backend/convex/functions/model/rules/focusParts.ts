import type { Goal } from "../schema";
import { MUSCLE_KEYS, type MuscleKey, musclesFor, normName } from "./muscles";

/** Words in a goal title that name a muscle area directly. */
const WORDS: [RegExp, MuscleKey[]][] = [
  [/\bshoulders?\b|\bdelts?\b/, ["shoulders"]],
  [/\bchest\b|\bpecs?\b/, ["chest"]],
  [/\bbiceps?\b/, ["biceps"]],
  [/\btriceps?\b/, ["triceps"]],
  [/\bforearms?\b|\bgrip\b/, ["forearms"]],
  [/\babs\b|\bcore\b/, ["abs"]],
  [/\bupper back\b/, ["upper_back"]],
  [/\blats?\b/, ["lats"]],
  [/\blower back\b/, ["lower_back"]],
  [/\bback\b/, ["upper_back", "lats"]],
  [/\bglutes?\b|\bbum\b/, ["glutes"]],
  [/\bhips?\b/, ["hips"]],
  [/\bquads?\b|\bthighs?\b|\blegs?\b/, ["quads"]],
  [/\bhamstrings?\b/, ["hamstrings"]],
  [/\bcalf\b|\bcalves\b/, ["calves"]],
];

/** Muscle keys named by the active goals: from the goal exercise and from words in the title. Canonical order. */
export function focusPartsFromGoals(goals: Pick<Goal, "title" | "exercise" | "status">[]): MuscleKey[] {
  const found = new Set<MuscleKey>();
  for (const g of goals) {
    if (g.status !== "active") continue;
    for (const text of [g.exercise, g.title]) {
      if (!text) continue;
      for (const k of musclesFor(text).primary) found.add(k);
      const n = normName(text);
      for (const [re, keys] of WORDS) if (re.test(n)) keys.forEach((k) => found.add(k));
    }
  }
  return MUSCLE_KEYS.filter((k) => found.has(k));
}
