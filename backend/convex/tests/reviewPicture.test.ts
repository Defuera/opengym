import { describe, expect, it } from "vitest";
import { buildReviewInput } from "../functions/model/ai/jobs/inputs";
import { reviewSessionJob } from "../functions/model/ai/jobs/reviewSession";
import type { ContextItem, Goal, Session } from "../functions/model/schema";

const DAY = 86_400_000;
const T = Date.UTC(2026, 10, 22, 14, 0, 0);
const gym = (id: string, endedAt: number, focus: string, kg: number, failed = false): Session => ({
  id, kind: "gym", type: "Gym", focus, startedAt: endedAt - 60 * 60_000, endedAt, source: "app",
  exercises: [{ name: "Leg Press", sets: [{ reps: 12, kg, max: false, ...(failed ? { failed: true } : {}) }], ...(failed ? { comment: "knee felt fine" } : {}) }],
});
const goals: Goal[] = [{ id: "g1", title: "Ski on 19 December", kind: "custom", status: "active", source: "user", createdAt: T - 30 * DAY }];
const context: ContextItem[] = [{ id: "c1", topic: "elbow", text: "Left elbow hurts", active: true, source: "user", createdAt: Date.UTC(2026, 10, 18, 9) }];

describe("review_session input", () => {
  const before = gym("a", T - 3 * DAY, "Ski prep", 30);
  const now = gym("b", T, "Legs", 35, true);
  const input = buildReviewInput([before, now], now, [], { goals, context });
  const prompt = reviewSessionJob.build(input);
  const data = JSON.parse(prompt.messages[0]!.content.split("INPUT_JSON:\n")[1]!);

  it("gives the coach the picture as it was before the session, across foci", () => {
    // The last Leg Press was in a session of another focus: the old review (same focus only) never saw it.
    expect(data.before.exercisesTheUserKnows).toEqual([expect.objectContaining({ name: "Leg Press", lastSets: "12x30", lastDone: "2026-11-19" })]);
    expect(data.before.goalsInOrderOfPriority[0].title).toBe("Ski on 19 December");
    expect(data.before.sessionsLogged).toBe(1);
  });

  it("shows the failed mark and the person's comment of the finished session", () => {
    expect(data.session.exercises[0]).toEqual({ name: "Leg Press", sets: "12x35 (last rep failed)", commentFromThePerson: "knee felt fine" });
  });

  it("dates every note about the person", () => {
    expect(data.before.notesFromTheUser).toEqual([{ topic: "elbow", text: "Left elbow hurts", stored: "2026-11-18" }]);
  });

  it("keeps the old bounded input when the caller gives no goals and notes", () => {
    const old = JSON.parse(reviewSessionJob.build(buildReviewInput([before, now], now)).messages[0]!.content.split("INPUT_JSON:\n")[1]!);
    expect(old.before).toBeUndefined();
    expect(old.recentSameType).toEqual([]);
  });
});
