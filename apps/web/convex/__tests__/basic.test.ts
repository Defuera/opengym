import { convexTest } from "convex-test";
import { expect, test } from "vitest";
import { api } from "../_generated/api";
import schema from "../schema";

test("users.create returns an id", async () => {
  const t = convexTest(schema);
  const userId = await t.mutation(api.users.create, { name: "Test User" });
  expect(userId).toBeDefined();
  expect(typeof userId).toBe("string");
});

test("sessions.list returns empty for new user", async () => {
  const t = convexTest(schema);
  const userId = await t.mutation(api.users.create, { name: "Test User" });
  const sessions = await t.query(api.sessions.list, { userId });
  expect(sessions).toEqual([]);
});

test("sessions.create and list round-trip", async () => {
  const t = convexTest(schema);
  const userId = await t.mutation(api.users.create, { name: "Test User" });

  const sessionId = await t.mutation(api.sessions.create, {
    userId,
    status: "active",
    exercises: [
      {
        name: "Bench Press",
        muscleGroup: "chest",
        order: 0,
        sets: [{ reps: 10, weight: 60, order: 0 }],
      },
    ],
  });
  expect(sessionId).toBeDefined();

  const sessions = await t.query(api.sessions.list, { userId });
  expect(sessions).toHaveLength(1);
  expect(sessions[0].status).toBe("active");
  expect(sessions[0].userId).toBe(userId);
});
