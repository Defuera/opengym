"use strict";
// Convex-backed workout repository
// Uses Convex queries and mutations for persistent storage
Object.defineProperty(exports, "__esModule", { value: true });
exports.workoutRepository = void 0;
const browser_1 = require("convex/browser");
const api_1 = require("../../../convex/_generated/api");
// Initialize Convex client for server-side use
const convexUrl = process.env.NEXT_PUBLIC_CONVEX_URL;
if (!convexUrl) {
    throw new Error("NEXT_PUBLIC_CONVEX_URL is not set. Please configure Convex deployment URL.");
}
const client = new browser_1.ConvexHttpClient(convexUrl);
// Type conversion helpers
function timestampToDate(ts) {
    return new Date(ts);
}
function idToString(id) {
    return id;
}
function stringToId(str) {
    return str;
}
// Cache for default user ID
let cachedDefaultUserId = null;
// Get or create the default user
async function getDefaultUserId() {
    if (cachedDefaultUserId) {
        return cachedDefaultUserId;
    }
    // Fetch or create the default user
    const userId = await client.mutation(api_1.api.users.getOrCreateDefaultUser, {});
    cachedDefaultUserId = userId;
    return userId;
}
// Resolve user ID (handle "default-user" string)
async function resolveUserId(userId) {
    if (userId === "default-user") {
        return getDefaultUserId();
    }
    return stringToId(userId);
}
// Convert Convex session with nested data to domain type
function convertSessionWithDetails(convexSession) {
    return {
        id: idToString(convexSession._id),
        userId: idToString(convexSession.userId),
        date: timestampToDate(convexSession.date),
        status: convexSession.status,
        createdAt: timestampToDate(convexSession.createdAt),
        updatedAt: timestampToDate(convexSession.updatedAt),
        exercises: convexSession.exercises.map((ex) => ({
            id: idToString(ex._id),
            sessionId: idToString(ex.sessionId),
            name: ex.name,
            muscleGroup: ex.muscleGroup,
            order: ex.order,
            sets: ex.sets.map((set) => ({
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
function convertSession(convexSession) {
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
exports.workoutRepository = {
    // Get user by ID
    async getUser(userId) {
        const convexUserId = await resolveUserId(userId);
        const convexUser = await client.query(api_1.api.users.get, { id: convexUserId });
        if (!convexUser)
            return null;
        return {
            id: idToString(convexUser._id),
            name: convexUser.name,
            createdAt: timestampToDate(convexUser.createdAt),
            unit: convexUser.unit ?? "metric",
        };
    },
    // Update user unit preference
    async updateUserUnit(userId, unit) {
        const convexUserId = await resolveUserId(userId);
        await client.mutation(api_1.api.users.updateUnit, {
            userId: convexUserId,
            unit,
        });
    },
    // List recent sessions for a user
    async listRecentSessionsForUser(userId, limit = 10) {
        const convexUserId = await resolveUserId(userId);
        const sessions = await client.query(api_1.api.sessions.listWithDetails, {
            userId: convexUserId,
            limit,
        });
        return sessions.map(convertSessionWithDetails);
    },
    // Get a single session with details
    async getSessionWithDetails(id) {
        const sessionId = stringToId(id);
        const session = await client.query(api_1.api.sessions.getWithDetails, {
            id: sessionId,
        });
        if (!session)
            return null;
        return convertSessionWithDetails(session);
    },
    // Get recent completed sessions for history analysis
    async getRecentCompletedSessions(userId, limit) {
        const convexUserId = await resolveUserId(userId);
        const sessions = await client.query(api_1.api.sessions.listRecentCompleted, {
            userId: convexUserId,
            limit,
        });
        return sessions.map(convertSessionWithDetails);
    },
    // Create a new session with exercises and sets
    async createSession(data) {
        const convexUserId = await resolveUserId(data.userId);
        const sessionId = await client.mutation(api_1.api.sessions.create, {
            userId: convexUserId,
            status: data.status,
            exercises: data.exercises,
        });
        // Fetch the created session with details
        const session = await client.query(api_1.api.sessions.getWithDetails, {
            id: sessionId,
        });
        if (!session) {
            throw new Error("Failed to fetch created session");
        }
        return convertSessionWithDetails(session);
    },
    // Update session status
    async updateSessionStatus(id, status) {
        const sessionId = stringToId(id);
        await client.mutation(api_1.api.sessions.updateStatus, {
            id: sessionId,
            status,
        });
        // Fetch the updated session
        const session = await client.query(api_1.api.sessions.get, { id: sessionId });
        if (!session)
            return null;
        return convertSession(session);
    },
    // Update a set's reps, weight, and/or status
    async updateSet(id, data) {
        const setId = stringToId(id);
        await client.mutation(api_1.api.sets.update, {
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
    async createSet(exerciseId, data) {
        const convexExerciseId = stringToId(exerciseId);
        const setId = await client.mutation(api_1.api.sets.create, {
            exerciseId: convexExerciseId,
            reps: data.reps,
            weight: data.weight,
            order: data.order,
        });
        return idToString(setId);
    },
    // Delete a set
    async deleteSet(id) {
        const setId = stringToId(id);
        await client.mutation(api_1.api.sets.remove, {
            id: setId,
        });
    },
    // Add a new exercise to a session
    async addExerciseToSession(sessionId, data) {
        const convexSessionId = stringToId(sessionId);
        const exerciseId = await client.mutation(api_1.api.exercises.addToSession, {
            sessionId: convexSessionId,
            name: data.name,
            muscleGroup: data.muscleGroup,
            sets: data.sets,
        });
        return idToString(exerciseId);
    },
    // Get last recorded values for an exercise by name
    async getLastValuesForExercise(exerciseName) {
        const userId = await getDefaultUserId();
        const lastValues = await client.query(api_1.api.exercises.getLastValuesByName, {
            userId,
            exerciseName,
        });
        return lastValues;
    },
};
