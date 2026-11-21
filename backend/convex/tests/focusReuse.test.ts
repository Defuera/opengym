import { describe, expect, it } from "vitest";
import { buildSessionJob } from "../functions/model/ai/jobs/buildSession";
import { finalizeStartProposal } from "../functions/model/proposals";
import { fociByUse } from "../functions/model/rules/foci";
import type { Session } from "../functions/model/schema";
import { buildStartInput } from "../functions/model/startInput";

const NOW = Date.UTC(2026, 10, 21, 12);
const DAY = 86_400_000;
const s = (id: string, daysAgo: number, type: string, focus?: string, kind: "gym" | "activity" = "gym"): Session => ({
  id,
  kind,
  type,
  ...(focus ? { focus } : {}),
  startedAt: NOW - daysAgo * DAY,
  endedAt: NOW - daysAgo * DAY,
  exercises: kind === "gym" ? [{ name: "Bench Press", sets: [{ reps: 8, kg: 60, max: false }] }] : [],
  source: "app",
});
// Oldest first, as the server reads the log.
const log = [s("a", 9, "Gym", "Upper"), s("b", 8, "Gym", "Legs"), s("c", 6, "Gym", "upper"), s("d", 5, "Gym", "Upper"), s("e", 2, "Gym", "Ski prep: legs and balance"), s("f", 1, "Run", "Easy", "activity"), s("g", 1, "Home", "Quick")];
const data = { sessions: log, goals: [], context: [], limits: [], places: [], entries: [], now: NOW };
const draft = (focus: string) => ({ kind: "gym" as const, type: "Gym", focus, plan: { rationale: "r", exercises: [{ name: "Bench Press", sets: [{ reps: 8, kg: 60, max: false }] }] } });

describe("the coach reuses a focus name of the log", () => {
  it("fociByUse lists the foci of one activity, most used first, in the log's most recent spelling", () => {
    expect(fociByUse(log, "gym")).toEqual([
      { focus: "Upper", timesLogged: 3 },
      { focus: "Ski prep: legs and balance", timesLogged: 1 },
      { focus: "Legs", timesLogged: 1 },
    ]);
    expect(fociByUse(log, "Run")).toEqual([]); // a time activity has no plan focus
  });

  it("a named request carries the foci of that activity only; a free request carries every activity with sets", () => {
    expect(buildStartInput({ name: "Gym" }, data).job.fociTheUserUses).toEqual([{ activity: "Gym", foci: fociByUse(log, "Gym") }]);
    expect(buildStartInput({ text: "quick home session" }, data).job.fociTheUserUses!.map((a) => a.activity).sort()).toEqual(["Gym", "Home"]);
    expect(buildStartInput({ name: "Padel" }, data).job.fociTheUserUses).toEqual([]);
  });

  it("the prompt holds the list and the rule", () => {
    const req = buildSessionJob.build(buildStartInput({ name: "Gym" }, data).job);
    expect(req.system).toContain("fociTheUserUses");
    expect(req.messages[0]!.content).toContain('"fociTheUserUses":[{"activity":"Gym"');
  });

  it("a focus the log has keeps the log's spelling; a new focus stays as given", () => {
    expect(finalizeStartProposal(draft("  UPPER "), log).focus).toBe("Upper");
    expect(finalizeStartProposal(draft("Pull"), log).focus).toBe("Pull");
  });
});
