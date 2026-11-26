import { vi } from "vitest";
import { api } from "../functions/_generated/api";
import { PER_USER_TABLES, type PerUserTable } from "../functions/lib/userTables";
import { TOKEN, pushSession, setup, settle, type T } from "./helpers";

/** A second user for tests (ADR-039). Its token reaches the server only through the test-only env APP_EXTRA_TOKENS. */
export const TOKEN_B = "test-token-b";
export const USER_A = "owner";
export const USER_B = "user-b";

export { PER_USER_TABLES, type PerUserTable };

/** Like `setup()`, plus a token for user B. */
export function setupTwo(): T {
  const t = setup();
  vi.stubEnv("APP_EXTRA_TOKENS", JSON.stringify({ [TOKEN_B]: USER_B }));
  return t;
}

export const NOW = Date.UTC(2026, 10, 25, 12, 0);

/**
 * Makes data for ONE user in every per-user table, through the real public functions and the jobs they start (mock AI provider).
 * The ids are the SAME for every user ("s1", "th1", ...) on purpose: ids made on the phone are unique per user only. The words carry `mark`,
 * so a test can see whose words it reads. Needs fake timers (vi.useFakeTimers) and a system time. Settles all jobs at the end.
 */
export async function seedUser(t: T, token: string, mark: string): Promise<void> {
  vi.stubEnv("AI_PROVIDER", "mock");
  const m = (fn: unknown, args: Record<string, unknown>) => t.mutation(fn as never, { token, ...args } as never);
  await m(api.commands.places.save, { placeId: "pl1", name: `Gym ${mark}`, text: `barbell ${mark}` });
  await m(api.commands.sessions.save, { session: { ...pushSession("s1", NOW - 86_400_000), note: `felt strong ${mark}`, placeId: "pl1" } });
  await m(api.commands.sessions.logText, { sessionId: "s2", type: "Run", text: `ran 5 km in 30 min ${mark}`, at: NOW - 3_600_000 });
  await m(api.commands.goals.create, { goalId: "g1", title: `Bench 80 ${mark}`, kind: "strength", exercise: "Bench press", targetKg: 80 });
  await m(api.commands.context.create, { itemId: "c1", text: `Prefers mornings ${mark}`, topic: "schedule" });
  await m(api.commands.limits.save, { limit: { limitId: "l1", part: "left_knee", title: `Left knee ${mark}`, status: "active", rules: [{ kind: "avoid", text: `No deep squats ${mark}`, exercises: ["Burpee"] }] } });
  await m(api.commands.limits.addRecord, { record: { recordId: "r1", limitId: "l1", title: `Scan ${mark}`, text: `record text ${mark}` } });
  await m(api.commands.limits.checkin, { checkin: { checkinId: "ck1", limitId: "l1", at: NOW, feeling: "fine" } });
  const storageId = await t.run((c) => c.storage.store(new Blob(["x"], { type: "image/jpeg" })));
  await m(api.commands.files.register, { fileId: "f1", storageId, name: `meal ${mark}.jpg`, mime: "image/jpeg", size: 1 });
  await m(api.commands.entries.save, { entry: { entryId: "e1", text: `Lunch ${mark}`, fileIds: ["f1"], at: NOW - 3_600_000, createdAt: NOW - 3_600_000 } });
  await m(api.commands.tracker.sync, { days: [{ date: "2026-11-24", steps: 8000 }], workouts: [{ workoutId: "w1", type: "Running", startedAt: NOW - 7_200_000, endedAt: NOW - 5_400_000, minutes: 30, sourceName: "Fitbit" }] });
  await m(api.commands.imports.loadStructured, { importId: "i1", sessions: [{ kind: "activity", type: "Walk", startedAt: NOW - 9 * 86_400_000, endedAt: NOW - 9 * 86_400_000 + 1_800_000, minutes: 30 }], note: `from sheet ${mark}` });
  await m(api.commands.openSession.put, { session: { id: "os1", kind: "gym", type: "Gym", focus: "Legs", startedAt: NOW, source: "app", exercises: [{ id: "x1", name: `Squat ${mark}`, sets: [{ reps: 8, kg: 50, done: false }] }] } });
  await m(api.commands.settings.setAiModel, { model: `model-${mark}` });
  await m(api.commands.threads.create, { threadId: "th1" });
  await m(api.commands.messages.send, { threadId: "th1", messageId: "m1", text: `hello coach ${mark}` });
  await m(api.commands.start.request, { requestId: "sr1", name: "Gym", text: `legs today ${mark}` });
  await m(api.commands.proposals.request, { proposalId: "p1", kind: "program", text: `knee for skiing ${mark}` });
  await settle(t);
  await m(api.commands.proposals.accept, { proposalId: "p1" });
  await m(api.commands.proposals.request, { proposalId: "p2", kind: "program", text: `second ${mark}` });
  await settle(t);
  await t.run(async (c) => {
    // `predictions` has no writer any more (a legacy read model); one row is made by hand so the table is covered.
    await c.db.insert("predictions", { userId: token === TOKEN ? USER_A : USER_B, version: 1, createdAt: NOW, source: "rules", items: [] });
  });
}

export { TOKEN };
