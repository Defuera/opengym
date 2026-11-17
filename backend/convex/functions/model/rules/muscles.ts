/** Muscle areas: get a load level and can be a focus. */
export const MUSCLE_KEYS = ["shoulders", "chest", "biceps", "triceps", "forearms", "abs", "upper_back", "lats", "lower_back", "glutes", "hips", "quads", "hamstrings", "calves"] as const;
/** Joints and spots: limits only. */
export const JOINT_KEYS = ["neck", "left_shoulder", "right_shoulder", "left_elbow", "right_elbow", "left_wrist", "right_wrist", "wrists", "left_knee", "right_knee", "left_ankle", "right_ankle"] as const;
export const PART_KEYS = [...MUSCLE_KEYS, ...JOINT_KEYS] as const;

export type MuscleKey = (typeof MUSCLE_KEYS)[number];
export interface Muscles {
  primary: MuscleKey[];
  secondary: MuscleKey[];
}

const m = (primary: MuscleKey[], secondary: MuscleKey[] = []): Muscles => ({ primary, secondary });

/** Exercise name (normalised, see normName) -> muscles it trains. */
const TABLE: Record<string, Muscles> = {
  "back extension": m(["lower_back"], ["glutes", "hamstrings"]),
  "bench press": m(["chest"], ["triceps", "shoulders"]),
  "biceps curl": m(["biceps"], ["forearms"]),
  dips: m(["chest", "triceps"], ["shoulders"]),
  "face pull": m(["upper_back", "shoulders"], ["biceps"]),
  "flat abs": m(["abs"]),
  "glute drive": m(["glutes"], ["hamstrings"]),
  "hammer shoulder press": m(["shoulders"], ["triceps"]),
  "shoulder press": m(["shoulders"], ["triceps"]),
  "hip abduction": m(["hips"], ["glutes"]),
  "hip adduction": m(["hips"]),
  "incline ab twist": m(["abs"]),
  "lat pulldown": m(["lats"], ["biceps", "upper_back"]),
  "wide grip lat pulldown": m(["lats"], ["biceps", "upper_back"]),
  "iso lateral lat pulldown": m(["lats"], ["biceps", "upper_back"]),
  "leg extension": m(["quads"]),
  "leg press": m(["quads"], ["glutes", "hamstrings"]),
  "low row": m(["upper_back", "lats"], ["biceps"]),
  "single arm low row": m(["upper_back", "lats"], ["biceps"]),
  "prone leg curl": m(["hamstrings"], ["calves"]),
  "pull up": m(["lats"], ["biceps", "upper_back"]),
  "reverse fly": m(["upper_back", "shoulders"]),
  "rope cable biceps curl": m(["biceps"], ["forearms"]),
  squat: m(["quads", "glutes"], ["hamstrings", "lower_back"]),
  "hack squat": m(["quads"], ["glutes"]),
  "standing cable hip abduction": m(["hips"], ["glutes"]),
  "standing calf raise": m(["calves"]),
  "straight leg raise": m(["abs"], ["hips", "quads"]),
  "superman raise": m(["lower_back"], ["glutes"]),
  "triceps rope pushdown": m(["triceps"]),
  "lateral raise": m(["shoulders"]),
  "pullover machine": m(["lats"], ["chest", "triceps"]),
  "incline dumbbell press": m(["chest"], ["shoulders", "triceps"]),
  "pec deck": m(["chest"]),
};

/** Lowercase, hyphens and punctuation become single spaces. */
export const normName = (name: string): string => name.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();

/** Keyword fallback for names not in the table. First matching rule wins. */
const KEYWORDS: [RegExp, Muscles][] = [
  [/\bcalf\b|\bcalves\b/, m(["calves"])],
  [/\babduct|\badduct/, m(["hips"], ["glutes"])],
  [/\bleg curl\b|\bhamstring/, m(["hamstrings"], ["calves"])],
  [/\bdeadlift\b|\brdl\b|\bromanian\b/, m(["hamstrings", "glutes", "lower_back"])],
  [/\bleg extension\b/, m(["quads"])],
  [/\bleg press\b/, m(["quads"], ["glutes", "hamstrings"])],
  [/\bsquat\b|\blunge|\bsplit squat\b|\bstep up\b/, m(["quads", "glutes"], ["hamstrings"])],
  [/\bthrust\b|\bbridge\b|\bglute/, m(["glutes"], ["hamstrings"])],
  [/\btricep|\bpushdown\b|\bskull|\bdip\b|\bdips\b/, m(["triceps"])],
  [/\bcurl\b|\bbicep/, m(["biceps"], ["forearms"])],
  [/\bwrist\b|\bforearm/, m(["forearms"])],
  [/\bshoulder press\b|\boverhead\b|\bmilitary\b|\barnold\b/, m(["shoulders"], ["triceps"])],
  [/\blateral raise\b|\bfront raise\b|\bupright row\b/, m(["shoulders"])],
  [/\bpulldown\b|\bpull up\b|\bpullup\b|\bchin up\b|\bchinup\b|\blat\b/, m(["lats"], ["biceps", "upper_back"])],
  [/\brow\b|\brows\b/, m(["upper_back", "lats"], ["biceps"])],
  [/\bbench\b/, m(["chest"], ["triceps", "shoulders"])],
  [/\bpress\b|\bpush up\b|\bpushup\b/, m(["chest", "shoulders"], ["triceps"])],
  [/\bfly\b|\bflye\b|\bpec\b|\bchest\b/, m(["chest"])],
  [/\bcrunch|\bplank\b|\bsit up\b|\bab\b|\babs\b|\bcore\b/, m(["abs"])],
  [/\bback extension\b|\bhyperextension\b/, m(["lower_back"], ["glutes"])],
];

/** Muscles for an exercise name: the table first, then keywords. Empty arrays when nothing fits. */
export function musclesFor(name: string): Muscles {
  const n = normName(name);
  return TABLE[n] ?? KEYWORDS.find(([re]) => re.test(n))?.[1] ?? m([]);
}

/** Every muscle an exercise trains, primary first. */
export const allMusclesFor = (name: string): MuscleKey[] => {
  const x = musclesFor(name);
  return [...x.primary, ...x.secondary];
};
