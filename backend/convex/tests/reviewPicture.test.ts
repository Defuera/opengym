import { describe, expect, it } from "vitest";
import { buildReviewInput } from "../functions/model/ai/jobs/inputs";
import { reviewData, reviewSessionJob } from "../functions/model/ai/jobs/reviewSession";
import type { ContextItem, Goal, Session } from "../functions/model/schema";
import { ReviewDraftSchema, ReviewSchema } from "../functions/model/schema";
import { finalizeReview } from "../functions/model/proposals";

const DAY = 86_400_000;
const T = Date.UTC(2026, 10, 22, 14, 0, 0);
const gym = (id: string, endedAt: number, focus: string, kg: number, failed = false): Session => ({
  id, kind: "gym", type: "Gym", focus, startedAt: endedAt - 60 * 60_000, endedAt, source: "app",
  exercises: [{ name: "Leg Press", sets: [{ reps: 12, kg, max: false, ...(failed ? { failed: true } : {}) }], ...(failed ? { comment: "knee felt fine" } : {}) }],
});
const goals: Goal[] = [{ id: "g1", title: "Ski on 19 December", kind: "custom", status: "active", source: "user", createdAt: T - 30 * DAY }];
const context: ContextItem[] = [{ id: "c1", topic: "elbow", text: "Left elbow hurts", active: true, source: "user", createdAt: Date.UTC(2026, 10, 18, 9) }];

describe("review_session input (ADR-041)", () => {
  const before = gym("a", T - 3 * DAY, "Ski prep", 30);
  const now = gym("b", T, "Legs", 35, true);
  const input = buildReviewInput([before, now], now, [], { goals, context });
  const prompt = reviewSessionJob.build(input);
  const data = JSON.parse(prompt.messages[0]!.content.split("INPUT_JSON:\n")[1]!);

  it("gives the facts, compared with the last time of the same exercise whatever the focus was", () => {
    expect(data.facts.exercises).toEqual([expect.objectContaining({ name: "Leg Press", bestToday: "12x35", lastTime: { date: "2026-11-19", best: "12x30" }, change: "+5 kg", daysSinceLast: 3, firstTime: false })]);
  });

  it("gives the goals and the dated notes of the person, and no log to read back", () => {
    expect(data.goalsInOrderOfPriority[0].title).toBe("Ski on 19 December");
    expect(data.notesFromTheUser).toEqual([{ topic: "elbow", text: "Left elbow hurts", stored: "2026-11-18" }]);
    expect(data.session).toBeUndefined();
    expect(data.before).toBeUndefined();
    expect(data.facts.commentsFromThePerson).toEqual([{ exercise: "Leg Press", text: "knee felt fine" }]);
  });

  it("works with no goals and notes from the caller", () => {
    const old = JSON.parse(reviewSessionJob.build(buildReviewInput([before, now], now)).messages[0]!.content.split("INPUT_JSON:\n")[1]!);
    expect(old.goalsInOrderOfPriority).toBeUndefined();
    expect(old.facts.exercises).toHaveLength(1);
  });

  it("keeps the limit rule and has no per-exercise line rules or wording safeguards", () => {
    expect(prompt.system).toContain("Apply a limit only to the body part and movement it names");
    expect(prompt.system).not.toMatch(/at most five short lines|safeguard|disclaimer/i);
  });

  it("refuses a number that is not in the data, and accepts the numbers of the facts", () => {
    const ok = { message: "Wow, 5 kg more on the leg press than 3 days ago. How is the knee?", question: { text: "How is the knee?", answers: ["Fine", "Sore"] } };
    expect(reviewSessionJob.check!(ok, input)).toBeNull();
    expect(reviewSessionJob.check!({ message: "That is 40 kg more." }, input)).toMatch(/number 40 is not in facts/);
    expect(JSON.stringify(reviewData(input))).toContain("12x35");
  });

  it("falls back to an empty message, which the job does not store", () => {
    expect(reviewSessionJob.fallback(input)).toEqual({ message: "" });
  });
});

describe("the review shape", () => {
  it("accepts a new review and an old one (summary and changes)", () => {
    expect(ReviewSchema.safeParse({ sessionId: "s", source: "ai", message: "Good.", question: { text: "How is the knee?", answers: [{ id: "a1", label: "Fine" }, { id: "a2", label: "Sore" }] } }).success).toBe(true);
    expect(ReviewSchema.safeParse({ sessionId: "s", source: "rules", summary: "Gym: 2 exercises.", changes: ["x"] }).success).toBe(true);
  });

  it("the draft needs 2 to 4 answers and a message", () => {
    expect(ReviewDraftSchema.safeParse({ message: "Good." }).success).toBe(true);
    expect(ReviewDraftSchema.safeParse({ message: "Good.", question: { text: "q", answers: ["only one"] } }).success).toBe(false);
    expect(ReviewDraftSchema.safeParse({ message: "Good.", question: { text: "q", answers: ["1", "2", "3", "4", "5"] } }).success).toBe(false);
    expect(ReviewDraftSchema.safeParse({ message: "" }).success).toBe(false);
  });

  it("code makes the answer ids", () => {
    expect(finalizeReview({ message: "Good.", question: { text: "Pain?", answers: ["No", "A bit"] } })).toEqual({ message: "Good.", question: { text: "Pain?", answers: [{ id: "a1", label: "No" }, { id: "a2", label: "A bit" }] } });
    expect(finalizeReview({ message: "Good." })).toEqual({ message: "Good." });
  });
});
