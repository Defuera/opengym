import { describe, expect, it } from "vitest";
import { slotOf, usualSessionNow } from "../functions/model/usualSession";
import type { Session } from "../functions/model/schema";
import { buildStartInput } from "../functions/model/startInput";

const TZ = "Europe/Madrid"; // UTC+1 in winter
const at = (day: number, h: number, m = 0) => Date.UTC(2026, 10, day, h - 1, m); // local time in Madrid, November 2026
const sess = (id: string, start: number, minutes: number, sets = 10, source: "app" | "import" = "app"): Session => ({
  id, kind: "gym", type: "Gym", startedAt: start, endedAt: start + minutes * 60000, source,
  exercises: [{ name: "Leg Press", sets: Array.from({ length: sets }, () => ({ reps: 10, kg: 20, max: false })) }],
});
// 2026-11-27 is a Friday. 23, 24, 25 are Mon, Tue, Wed. 21 is a Saturday.
const now = at(27, 8, 30);

describe("the slot of a time", () => {
  it("uses the time zone of the user", () => {
    expect(slotOf(at(27, 8, 30), TZ)).toEqual({ weekend: false, part: "morning" });
    expect(slotOf(at(27, 16, 59), TZ).part).toBe("afternoon");
    expect(slotOf(at(27, 17, 0), TZ).part).toBe("evening");
    expect(slotOf(at(21, 9), TZ).weekend).toBe(true);
    // 23:30 UTC on Friday is 00:30 on Saturday in Madrid.
    expect(slotOf(Date.UTC(2026, 10, 27, 23, 30), TZ)).toEqual({ weekend: true, part: "morning" });
  });
});

describe("the usual session at this time of the week (ADR-042)", () => {
  const morning = [sess("a", at(23, 8, 17), 53, 12), sess("b", at(24, 8, 30), 75, 10), sess("c", at(25, 8, 45), 76, 14), sess("d", at(26, 8, 20), 71, 10), sess("e", at(20, 8, 20), 103, 16)];

  it("is the median of the weekday morning sessions", () => {
    expect(usualSessionNow(morning, now, TZ)).toEqual({ when: "weekday morning", sessions: 5, usualMinutes: 75, usualSets: 12 });
  });

  it("skips imported sessions, too short, too long and unfinished ones", () => {
    const noise = [sess("i", at(23, 8), 60, 10, "import"), sess("s", at(23, 8), 5), sess("l", at(23, 8), 300), sess("z", at(23, 8), 0)];
    expect(usualSessionNow([...morning, ...noise], now, TZ)?.sessions).toBe(5);
  });

  it("skips sessions older than 8 weeks", () => {
    expect(usualSessionNow([...morning.slice(0, 2), sess("old", at(27, 8) - 60 * 86_400_000, 60)], now, TZ)).toBeNull();
  });

  it("falls back to all weekday sessions when the slot has fewer than 3", () => {
    const mixed = [morning[0]!, morning[1]!, sess("p", at(25, 18), 60, 8), sess("q", at(26, 13), 40, 6)];
    expect(usualSessionNow(mixed, now, TZ)).toEqual({ when: "weekday", sessions: 4, usualMinutes: 57, usualSets: 9 });
  });

  it("does not mix weekend sessions into a weekday and is null with fewer than 3", () => {
    const weekend = [sess("w1", at(21, 9), 90), sess("w2", at(22, 9), 90), sess("w3", at(14, 9), 90)];
    expect(usualSessionNow(weekend, now, TZ)).toBeNull();
    expect(usualSessionNow(weekend, at(28, 9), TZ)?.when).toBe("weekend morning");
  });

  it("goes into the build_session input, and only when known", () => {
    const d = { sessions: morning, goals: [], context: [], limits: [], places: [], entries: [], now, timeZone: TZ };
    expect(buildStartInput({ name: "Gym" }, d).job.usualSessionNow?.usualMinutes).toBe(75);
    expect(buildStartInput({ name: "Gym" }, { ...d, sessions: [] }).job.usualSessionNow).toBeUndefined();
    expect(buildStartInput({ name: "Gym", feedback: ["shorter"] }, d).job.usualSessionNow?.when).toBe("weekday morning");
  });
});
