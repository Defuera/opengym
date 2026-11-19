/**
 * The check of an exercise picture (pure code): does the figure stay on the same place in both poses?
 * The picture holds the start pose in the left half and the end pose in the right half. The parts that do not
 * move (the body, the equipment) must sit on the same place in both halves, else the figure jumps in the animation.
 * The app has the same measure (`poseShift` in `apps/mobile/lib/widgets/exercise_anim.dart`); keep the two alike.
 */
import { decode } from "fast-png";

export interface Shift {
  /** How far the end pose must move to sit on the start pose, in parts of the width and height of one half. */
  dx: number;
  dy: number;
}

const W = 192;
const H = 128;

/** The largest shift that does not count as a jump. */
export const ART_SHIFT_MAX = 0.03;

export const jumps = (s: Shift): boolean => Math.abs(s.dx) > ART_SHIFT_MAX || Math.abs(s.dy) > ART_SHIFT_MAX;
export const shiftSize = (s: Shift): number => Math.max(Math.abs(s.dx), Math.abs(s.dy));

/** The shift from a small picture of darkness values (0 light .. 255 dark), `w` x `h`, row by row. */
export function shiftOfDark(dark: Uint8Array, w: number, h: number): Shift {
  const hw = Math.floor(w / 2);
  const at = (x: number, y: number): number => {
    const d = dark[y * w + x]!;
    return d < 60 ? 0 : d;
  };
  const a = new Uint8Array(hw * h);
  const b = new Uint8Array(hw * h);
  for (let y = 0; y < h; y++)
    for (let x = 0; x < hw; x++) {
      a[y * hw + x] = at(x, y);
      b[y * hw + x] = at(x + hw, y);
    }
  const score = (dx: number, dy: number): number => {
    let sum = 0;
    for (let y = Math.max(0, dy); y < Math.min(h, h + dy); y++)
      for (let x = Math.max(0, dx); x < Math.min(hw, hw + dx); x++) sum += Math.min(a[y * hw + x]!, b[(y - dy) * hw + (x - dx)]!);
    return sum;
  };
  const maxDx = Math.round(hw * 0.2);
  const maxDy = Math.round(h * 0.05);
  const zero = score(0, 0);
  let best = zero;
  let bx = 0;
  let by = 0;
  for (let dy = -maxDy; dy <= maxDy; dy++)
    for (let dx = -maxDx; dx <= maxDx; dx++) {
      const s = score(dx, dy);
      if (s > best) [best, bx, by] = [s, dx, dy];
    }
  if (best * 100 < zero * 105) return { dx: 0, dy: 0 };
  return { dx: bx / hw, dy: by / h };
}

/** The shift of a PNG picture, measured on a small copy. Null when the bytes are not a picture this code can read. */
export function shiftOfPng(bytes: Uint8Array): Shift | null {
  try {
    const img = decode(bytes);
    const { width, height, channels, depth } = img;
    if (width < W || height < H || depth !== 8 || img.palette) return null;
    const data = img.data as Uint8Array;
    const sum = new Float64Array(W * H);
    const count = new Uint32Array(W * H);
    for (let y = 0; y < height; y++) {
      const sy = Math.min(H - 1, Math.floor((y * H) / height));
      for (let x = 0; x < width; x++) {
        const i = (y * width + x) * channels;
        const lum = channels >= 3 ? (data[i]! * 54 + data[i + 1]! * 183 + data[i + 2]! * 19) >> 8 : data[i]!;
        const k = sy * W + Math.min(W - 1, Math.floor((x * W) / width));
        sum[k]! += 255 - lum;
        count[k]!++;
      }
    }
    const dark = new Uint8Array(W * H);
    for (let k = 0; k < dark.length; k++) dark[k] = Math.round(sum[k]! / count[k]!);
    return shiftOfDark(dark, W, H);
  } catch {
    return null;
  }
}
