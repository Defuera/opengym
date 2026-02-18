// Convex-backed workout repository
// Uses Convex queries and mutations for persistent storage

import { ConvexHttpClient } from "convex/browser";
import { api } from "../../../convex/_generated/api";
import {
  Id,
  type TableNames,
} from "../../../convex/_generated/dataModel";
import type {
  User,
  Session,
  Exercise,
  Set,
  SessionWithExercisesAndSets,
} from "./types";

// Initialize Convex client for server-side use
const convexUrl = process.env.NEXT_PUBLIC_CONVEX_URL!;
if (!convexUrl) {
  throw new Error(
    "NEXT_PUBLIC_CONVEX_URL is not set. Please configure Convex deployment URL."
  );
}
const client = new ConvexHttpClient(convexUrl);

// Type conversion helpers
function timestampToDate(ts: number): Date {
  return new Date(ts);
}

function idToString<T extends TableNames>(id: Id<T>): string {
  return id as string;
}

function stringToId<T extends TableNames>(str: string): Id<T> {
  return str as Id<T>;
}

// Cache for default user ID
let cachedDefaultUserId: Id<"users"> | null = null;

// Get or create the default user
async function getDefaultUserId(): Promise<Id<"users">> {
  if (cachedDefaultUserId) {
    return cachedDefaultUserId;
  }

  // Fetch or create the default user
  const userId = await client.mutation(api.users.getOrCreateDefaultUser, {});
  cachedDefaultUserId = userId;
  return userId;
}

// Resolve user ID (handle "default-user" string)
async function resolveUserId(userId: string): Promise<Id<"users">> {
  if (userId === "default-user") {
    return getDefaultUserId();
  }
  return stringToId<"users">(userId);
}

// Convert Convex session with nested data to domain type
function convertSessionWithDetails(
  convexSession: any
): SessionWithExercisesAndSets {
  return {
    id: idToString(convexSession._id),
    userId: idToString(convexSession.userId),
    date: timestampToDate(convexSession.date),
    status: convexSession.status,
    createdAt: timestampToDate(convexSession.createdAt),
    updatedAt: timestampToDate(convexSession.updatedAt),
    exercises: convexSession.exercises.map((ex: any) => ({
      id: idToString(ex._id),
      sessionId: idToString(ex.sessionId),
      name: ex.name,
      muscleGroup: ex.muscleGroup,
      order: ex.order,
      sets: ex.sets.map((set: any) => ({
        id: idToString(set._id),
        exerciseId: idToString(set.exerciseId),
        reps: set.reps,
        weight: set.weight,
        order: set.order,
        status: set.status ?? "todo",
      })),
    })),
  };
}

// Convert Convex session (without nested data) to domain type
function convertSession(convexSession: any): Session {
  return {
    id: idToString(convexSession._id),
    userId: idToString(convexSession.userId),
    date: timestampToDate(convexSession.date),
    status: convexSession.status,
    createdAt: timestampToDate(convexSession.createdAt),
    updatedAt: timestampToDate(convexSession.updatedAt),
  };
}

// Repository implementation
export const workoutRepository = {
  // List recent sessions for a user
  async listRecentSessionsForUser(
    userId: string,
    limit: number = 10
  ): Promise<SessionWithExercisesAndSets[]> {
    const convexUserId = await resolveUserId(userId);
    const sessions = await client.query(api.sessions.listWithDetails, {
      userId: convexUserId,
      limit,
    });

    return sessions.map(convertSessionWithDetails);
  },

  // Get a single session with details
  async getSessionWithDetails(
    id: string
  ): Promise<SessionWithExercisesAndSets | null> {
    const sessionId = stringToId<"sessions">(id);
    const session = await client.query(api.sessions.getWithDetails, {
      id: sessionId,
    });

    if (!session) return null;
    return convertSessionWithDetails(session);
  },

  // Get recent completed sessions for history analysis
  async getRecentCompletedSessions(
    userId: string,
    limit: number
  ): Promise<SessionWithExercisesAndSets[]> {
    const convexUserId = await resolveUserId(userId);
    const sessions = await client.query(api.sessions.listRecentCompleted, {
      userId: convexUserId,
      limit,
    });

    return sessions.map(convertSessionWithDetails);
  },

  // Create a new session with exercises and sets
  async createSession(data: {
    userId: string;
    status: "planned" | "active" | "completed";
    exercises: Array<{
      name: string;
      muscleGroup: string;
      order: number;
      sets: Array<{
        reps: number;
        weight: number;
        order: number;
      }>;
    }>;
  }): Promise<SessionWithExercisesAndSets> {
    const convexUserId = await resolveUserId(data.userId);
    const sessionId = await client.mutation(api.sessions.create, {
      userId: convexUserId,
      status: data.status,
      exercises: data.exercises,
    });

    // Fetch the created session with details
    const session = await client.query(api.sessions.getWithDetails, {
      id: sessionId,
    });

    if (!session) {
      throw new Error("Failed to fetch created session");
    }

    return convertSessionWithDetails(session);
  },

  // Update session status
  async updateSessionStatus(
    id: string,
    status: "planned" | "active" | "completed"
  ): Promise<Session | null> {
    const sessionId = stringToId<"sessions">(id);

    await client.mutation(api.sessions.updateStatus, {
      id: sessionId,
      status,
    });

    // Fetch the updated session
    const session = await client.query(api.sessions.get, { id: sessionId });

    if (!session) return null;
    return convertSession(session);
  },

  // Update a set's reps, weight, and/or status
  async updateSet(
    id: string,
    data: { reps?: number; weight?: number; status?: "todo" | "later" | "complete" }
  ): Promise<Set | null> {
    const setId = stringToId<"sets">(id);

    await client.mutation(api.sets.update, {
      id: setId,
      reps: data.reps,
      weight: data.weight,
      status: data.status,
    });

    // Note: Convex doesn't have a direct way to fetch a single set
    // In practice, this is called during a session, so the UI will refetch the session
    // For now, we construct a partial set response
    // In production, you might want to add a query to fetch a single set
    return {
      id,
      exerciseId: "", // Not available without additional query
      reps: data.reps ?? 0,
      weight: data.weight ?? 0,
      order: 0, // Not available without additional query
      status: data.status ?? "todo",
    };
  },

  // Create a new set for an exercise
  async createSet(
    exerciseId: string,
    data: { reps: number; weight: number; order: number }
  ): Promise<string> {
    const convexExerciseId = stringToId<"exercises">(exerciseId);

    const setId = await client.mutation(api.sets.create, {
      exerciseId: convexExerciseId,
      reps: data.reps,
      weight: data.weight,
      order: data.order,
    });

    return idToString(setId);
  },

  // Delete a set
  async deleteSet(id: string): Promise<void> {
    const setId = stringToId<"sets">(id);

    await client.mutation(api.sets.remove, {
      id: setId,
    });
  },

  // Add a new exercise to a session
  async addExerciseToSession(
    sessionId: string,
    data: {
      name: string;
      muscleGroup: string;
      sets: Array<{
        reps: number;
        weight: number;
        order: number;
      }>;
    }
  ): Promise<string> {
    const convexSessionId = stringToId<"sessions">(sessionId);

    const exerciseId = await client.mutation(api.exercises.addToSession, {
      sessionId: convexSessionId,
      name: data.name,
      muscleGroup: data.muscleGroup,
      sets: data.sets,
    });

    return idToString(exerciseId);
  },

  // Get last recorded values for an exercise by name
  async getLastValuesForExercise(
    exerciseName: string
  ): Promise<{ reps: number; weight: number } | null> {
    const userId = await getDefaultUserId();

    const lastValues = await client.query(api.exercises.getLastValuesByName, {
      userId,
      exerciseName,
    });

    return lastValues;
  },
};
