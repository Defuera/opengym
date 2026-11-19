/** Exercise art (pure code, no Convex imports): the key of an exercise, the shortlist of source exercises, and the image prompt. */

export interface SourceExercise {
  id: string;
  name: string;
  equipment: string;
  muscles: string[];
}

/** Longest exercise name the art functions take. */
export const ART_NAME_MAX = 80;

/** Key of an exercise: trimmed, lower case, runs of white space made one space. */
export const artKey = (name: string): string => name.trim().toLowerCase().replace(/\s+/g, " ");

const words = (name: string): string[] =>
  name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .split(" ")
    .filter(Boolean)
    .map((w) => (w.length > 3 && w.endsWith("s") ? w.slice(0, -1) : w));

const norm = (name: string): string => words(name).join(" ");

/** Candidates by word overlap of normalised names; an exact normalised match goes first. [] when no word overlaps. */
export function shortlist(name: string, exercises: SourceExercise[], n = 12): SourceExercise[] {
  const target = norm(name);
  const wanted = new Set(words(name));
  const scored = exercises
    .map((e, i) => {
      const w = words(e.name);
      const overlap = w.filter((x) => wanted.has(x)).length;
      return { e, i, overlap, exact: norm(e.name) === target, extra: w.length - overlap };
    })
    .filter((s) => s.overlap > 0);
  scored.sort((a, b) => Number(b.exact) - Number(a.exact) || b.overlap - a.overlap || a.extra - b.extra || a.i - b.i);
  return scored.slice(0, n).map((s) => s.e);
}

/** The image prompt. Two panels in one image: start position left, end position right. */
export function artPrompt(i: { name: string; muscles: string[]; hasPhotos: boolean; movement?: string }): string {
  const first = i.hasPhotos
    ? `Redraw the two reference photos as ONE flat illustration with two panels side by side, equal width: LEFT panel = the start position (first photo), RIGHT panel = the end position (second photo) of the exercise "${i.name}". Keep each pose and the equipment exactly as in its photo. The figure and the equipment have the same size and the same place in both panels, so that the two panels can be shown one after the other as an animation; only the moving body parts and moving machine parts differ.`
    : `Draw ONE flat illustration with two panels side by side, equal width: LEFT panel = the start position, RIGHT panel = the end position of one repetition of the exercise "${i.name}", with correct technique, seen from the side.${i.movement ? ` The movement: ${i.movement}` : ""} The figure and the equipment have the same size and the same place in both panels, so that the two panels can be shown one after the other as an animation; only the moving body parts and moving machine parts differ.`;
  const bracket = i.muscles.length > 0 ? ` (${i.muscles.join(", ")})` : "";
  return `${first} Each panel has a clear margin on all sides, and nothing crosses the vertical middle of the image.\n\nStyle: flat vector illustration, bold black outline of even thickness, rounded friendly shapes, a faceless bald mannequin-like figure, body filled white, the working muscles${bracket} filled solid royal blue #2448E8, equipment in light grey #E4E2DA with the same black outline, plain off-white background #F2F1EC in the whole image, no shading, no gradients, no shadows, no text, no numbers, no frame lines, no divider between the panels.`;
}
