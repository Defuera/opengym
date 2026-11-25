// @vitest-environment node
import { describe, expect, it } from "vitest";
import { KINDS_BY_JOB } from "../evals/assertions";
import { lackedIn } from "../evals/assertions/equipment";
import { CASES } from "../evals/cases";
import { NOW, PERSONAS, persona, placeOf } from "../evals/fixtures";
import { avoidedExercises } from "../functions/model/rules/limits";
import { normName } from "../functions/model/rules/muscles";
import { ContextItemSchema, GoalSchema, LimitSchema, SessionSchema } from "../functions/model/schema";

const DAY = 86_400_000;
const people = Object.values(PERSONAS);

describe("eval fixtures", () => {
  for (const p of people) {
    describe(`persona ${p.id}`, () => {
      it("every record has the real domain shape", () => {
        for (const s of p.sessions) expect(SessionSchema.safeParse(s).success, s.id).toBe(true);
        for (const g of p.goals) expect(GoalSchema.safeParse(g).success, g.id).toBe(true);
        for (const l of p.limits) expect(LimitSchema.safeParse(l).success, l.limitId).toBe(true);
        for (const c of p.context) expect(ContextItemSchema.safeParse(c).success, c.id).toBe(true);
        expect(new Set(p.sessions.map((s) => s.id)).size).toBe(p.sessions.length);
      });

      it("dates are ordered, in the past, and cover the last four weeks", () => {
        const ends = p.sessions.map((s) => s.endedAt);
        expect(ends).toEqual([...ends].sort((a, b) => a - b));
        for (const s of p.sessions) {
          expect(s.startedAt).toBeLessThanOrEqual(s.endedAt);
          expect(s.endedAt).toBeLessThan(NOW);
          expect(s.endedAt).toBeGreaterThan(NOW - 29 * DAY);
        }
        for (const g of [...p.goals, ...p.context]) expect(g.createdAt).toBeLessThan(NOW);
      });

      it("a session uses only a place of the persona, and no equipment that place lacks", () => {
        for (const s of p.sessions) {
          if (s.placeId === undefined) continue;
          const place = p.places.find((x) => x.placeId === s.placeId);
          expect(place, `${s.id} place`).toBeDefined();
          expect(lackedIn(s.exercises.map((e) => e.name).join("\n"), place!), s.id).toEqual([]);
        }
      });

      it("no session holds a movement a limit marks avoid", () => {
        const avoid = avoidedExercises(p.limits);
        for (const s of p.sessions) for (const e of s.exercises) expect(avoid.has(normName(e.name)), `${s.id} ${e.name}`).toBe(false);
      });

      it("each place has a text, and keyword lists that do not overlap", () => {
        for (const pl of p.places) {
          expect(pl.has.filter((h) => pl.lacks.includes(h))).toEqual([]);
          expect(lackedIn(pl.has.join(" "), pl)).toEqual([]);
        }
      });
    });
  }

  it("personas have the facts the cases rely on", () => {
    expect(persona("jonas").limits[0]!.rules.some((r) => r.kind === "avoid" && r.exercises?.includes("Leg extension"))).toBe(true);
    expect(placeOf(persona("mara"), "home").has).toContain("dumbbell");
    expect(placeOf(persona("jonas"), "HOME").has).toEqual([]);
    expect(persona("nia").sessions).toEqual([]);
  });
});

describe("eval cases", () => {
  it("ids are unique and there are about thirty, split as the design says", () => {
    expect(new Set(CASES.map((c) => c.id)).size).toBe(CASES.length);
    const n = (job: string) => CASES.filter((c) => c.job === job).length;
    expect([n("build_session"), n("chat"), n("parse_log"), n("learn_place")]).toEqual([14, 9, 6, 4]);
  });

  it("each case names a persona and places that exist, and uses only checks that fit its job", () => {
    for (const c of CASES) {
      const p = persona(c.persona);
      if (c.job === "chat" && c.place) placeOf(p, c.place);
      if (c.job === "learn_place") placeOf(p, c.place);
      if (c.job === "build_session") for (const k of Object.keys(c.placeText ?? {})) placeOf(p, k);
      for (const ch of [...c.gates, ...c.expect, ...(c.warn ?? [])]) {
        // A build case may read the raw type too; every kind must be allowed for the job.
        expect(KINDS_BY_JOB[c.job], `${c.id} ${ch.kind}`).toContain(ch.kind);
        for (const pat of "any" in ch ? (ch.any ?? []) : []) if (typeof pat !== "string") expect(() => new RegExp(pat.re, pat.flags)).not.toThrow();
      }
      expect(c.about.length, c.id).toBeGreaterThan(10);
    }
  });

  it("every chat case has fixed user turns, and a build rebuild has a previous plan", () => {
    for (const c of CASES) {
      if (c.job === "chat") expect(c.turns.length).toBeGreaterThan(0);
      if (c.job === "build_session" && c.feedback) expect(c.previousPlan).toBeDefined();
    }
  });
});
