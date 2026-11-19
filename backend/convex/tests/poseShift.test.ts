import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { jumps, shiftOfDark, shiftOfPng } from "../functions/model/poseShift";

const png = (name: string) => new Uint8Array(readFileSync(new URL(`./fixtures/${name}`, import.meta.url)));

/** Real pictures the image model made (made smaller). They fix what the check must say. */
describe("the check that the figure stays in place", () => {
  it("finds the jump in a real picture where the figure moved a lot", () => {
    const s = shiftOfPng(png("art-jump.png"))!;
    expect(s.dx).toBeCloseTo(17 / 96, 1);
    expect(jumps(s)).toBe(true);
  });

  it("finds the jump in a real picture where the figure moved a little", () => {
    const s = shiftOfPng(png("art-small-jump.png"))!;
    expect(s.dx).toBeGreaterThan(0.03);
    expect(s.dx).toBeLessThan(0.08);
    expect(jumps(s)).toBe(true);
  });

  it("passes the same picture with the figure put back in place", () => {
    const s = shiftOfPng(png("art-steady.png"))!;
    expect(jumps(s)).toBe(false);
  });

  it("gives null for bytes that are not a picture", () => {
    expect(shiftOfPng(new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]))).toBeNull();
    expect(shiftOfPng(new TextEncoder().encode("PNGBYTES"))).toBeNull();
  });

  it("is zero for an empty picture", () => {
    expect(shiftOfDark(new Uint8Array(192 * 128), 192, 128)).toEqual({ dx: 0, dy: 0 });
  });
});
