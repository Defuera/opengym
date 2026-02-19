"use strict";
// In-memory workout repository
// Stores sessions, exercises, and sets in module-level maps
Object.defineProperty(exports, "__esModule", { value: true });
exports.workoutRepository = void 0;
// Module-level storage
const users = new Map();
const sessions = new Map();
const exercises = new Map();
const sets = new Map();
const exerciseLastValues = new Map();
// ID generator
let idCounter = 0;
function generateId(prefix) {
    return `${prefix}_${Date.now()}_${++idCounter}`;
}
// Seed initial data on first access
let seeded = false;
function ensureSeeded() {
    if (seeded)
        return;
    seeded = true;
    // Create default user
    const defaultUser = {
        id: "default-user",
        name: "Default User",
        createdAt: new Date(),
    };
    users.set(defaultUser.id, defaultUser);
    // Seed two example sessions
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const twoDaysAgo = new Date();
    twoDaysAgo.setDate(twoDaysAgo.getDate() - 2);
    // Session 1: Completed push workout
    const session1 = {
        id: generateId("session"),
        userId: "default-user",
        date: twoDaysAgo,
        status: "completed",
        createdAt: twoDaysAgo,
        updatedAt: twoDaysAgo,
    };
    sessions.set(session1.id, session1);
    const ex1 = {
        id: generateId("exercise"),
        sessionId: session1.id,
        name: "Bench Press",
        muscleGroup: "chest",
        order: 1,
    };
    exercises.set(ex1.id, ex1);
    const ex2 = {
        id: generateId("exercise"),
        sessionId: session1.id,
        name: "Overhead Press",
        muscleGroup: "shoulders",
        order: 2,
    };
    exercises.set(ex2.id, ex2);
    // Add sets for ex1
    [
        { reps: 10, weight: 135 },
        { reps: 8, weight: 155 },
        { reps: 6, weight: 185 },
    ].forEach((data, idx) => {
        const set = {
            id: generateId("set"),
            exerciseId: ex1.id,
            reps: data.reps,
            weight: data.weight,
            order: idx + 1,
            status: "complete",
        };
        sets.set(set.id, set);
    });
    // Add sets for ex2
    [
        { reps: 10, weight: 95 },
        { reps: 8, weight: 115 },
        { reps: 8, weight: 115 },
    ].forEach((data, idx) => {
        const set = {
            id: generateId("set"),
            exerciseId: ex2.id,
            reps: data.reps,
            weight: data.weight,
            order: idx + 1,
            status: "complete",
        };
        sets.set(set.id, set);
    });
    // Session 2: Completed pull workout
    const session2 = {
        id: generateId("session"),
        userId: "default-user",
        date: yesterday,
        status: "completed",
        createdAt: yesterday,
        updatedAt: yesterday,
    };
    sessions.set(session2.id, session2);
    const ex3 = {
        id: generateId("exercise"),
        sessionId: session2.id,
        name: "Pull-ups",
        muscleGroup: "back",
        order: 1,
    };
    exercises.set(ex3.id, ex3);
    const ex4 = {
        id: generateId("exercise"),
        sessionId: session2.id,
        name: "Barbell Rows",
        muscleGroup: "back",
        order: 2,
    };
    exercises.set(ex4.id, ex4);
    // Add sets for ex3
    [
        { reps: 8, weight: 0 },
        { reps: 7, weight: 0 },
        { reps: 6, weight: 0 },
    ].forEach((data, idx) => {
        const set = {
            id: generateId("set"),
            exerciseId: ex3.id,
            reps: data.reps,
            weight: data.weight,
            order: idx + 1,
            status: "complete",
        };
        sets.set(set.id, set);
    });
    // Add sets for ex4
    [
        { reps: 10, weight: 135 },
        { reps: 10, weight: 155 },
        { reps: 8, weight: 175 },
    ].forEach((data, idx) => {
        const set = {
            id: generateId("set"),
            exerciseId: ex4.id,
            reps: data.reps,
            weight: data.weight,
            order: idx + 1,
            status: "complete",
        };
        sets.set(set.id, set);
    });
    // Seed last values for these exercises
    exerciseLastValues.set("Bench Press", {
        reps: 6,
        weight: 185,
        updatedAt: twoDaysAgo,
    });
    exerciseLastValues.set("Overhead Press", {
        reps: 8,
        weight: 115,
        updatedAt: twoDaysAgo,
    });
    exerciseLastValues.set("Pull-ups", {
        reps: 6,
        weight: 0,
        updatedAt: yesterday,
    });
    exerciseLastValues.set("Barbell Rows", {
        reps: 8,
        weight: 175,
        updatedAt: yesterday,
    });
}
// Repository implementation
exports.workoutRepository = {
    // List recent sessions for a user
    async listRecentSessionsForUser(userId, limit = 10) {
        ensureSeeded();
        const userSessions = Array.from(sessions.values())
            .filter((s) => s.userId === userId)
            .sort((a, b) => b.date.getTime() - a.date.getTime())
            .slice(0, limit);
        return userSessions.map((session) => {
            const sessionExercises = Array.from(exercises.values())
                .filter((ex) => ex.sessionId === session.id)
                .sort((a, b) => a.order - b.order);
            const exercisesWithSets = sessionExercises.map((exercise) => {
                const exerciseSets = Array.from(sets.values())
                    .filter((set) => set.exerciseId === exercise.id)
                    .sort((a, b) => a.order - b.order);
                return {
                    ...exercise,
                    sets: exerciseSets,
                };
            });
            return {
                ...session,
                exercises: exercisesWithSets,
            };
        });
    },
    // Get a single session with details
    async getSessionWithDetails(id) {
        ensureSeeded();
        const session = sessions.get(id);
        if (!session)
            return null;
        const sessionExercises = Array.from(exercises.values())
            .filter((ex) => ex.sessionId === session.id)
            .sort((a, b) => a.order - b.order);
        const exercisesWithSets = sessionExercises.map((exercise) => {
            const exerciseSets = Array.from(sets.values())
                .filter((set) => set.exerciseId === exercise.id)
                .sort((a, b) => a.order - b.order);
            return {
                ...exercise,
                sets: exerciseSets,
            };
        });
        return {
            ...session,
            exercises: exercisesWithSets,
        };
    },
    // Get recent completed sessions for history analysis
    async getRecentCompletedSessions(userId, limit) {
        ensureSeeded();
        const completedSessions = Array.from(sessions.values())
            .filter((s) => s.userId === userId && s.status === "completed")
            .sort((a, b) => b.date.getTime() - a.date.getTime())
            .slice(0, limit);
        return Promise.all(completedSessions.map(async (session) => {
            const result = await this.getSessionWithDetails(session.id);
            if (!result)
                throw new Error(`Session ${session.id} not found`);
            return result;
        }));
    },
    // Create a new session with exercises and sets
    async createSession(data) {
        ensureSeeded();
        const now = new Date();
        const session = {
            id: generateId("session"),
            userId: data.userId,
            date: now,
            status: data.status,
            createdAt: now,
            updatedAt: now,
        };
        sessions.set(session.id, session);
        const exercisesWithSets = data.exercises.map((exData) => {
            const exercise = {
                id: generateId("exercise"),
                sessionId: session.id,
                name: exData.name,
                muscleGroup: exData.muscleGroup,
                order: exData.order,
            };
            exercises.set(exercise.id, exercise);
            const exerciseSets = exData.sets.map((setData) => {
                const set = {
                    id: generateId("set"),
                    exerciseId: exercise.id,
                    reps: setData.reps,
                    weight: setData.weight,
                    order: setData.order,
                    status: "todo",
                };
                sets.set(set.id, set);
                return set;
            });
            return {
                ...exercise,
                sets: exerciseSets,
            };
        });
        return {
            ...session,
            exercises: exercisesWithSets,
        };
    },
    // Update session status
    async updateSessionStatus(id, status) {
        ensureSeeded();
        const session = sessions.get(id);
        if (!session)
            return null;
        const updated = {
            ...session,
            status,
            updatedAt: new Date(),
        };
        sessions.set(id, updated);
        return updated;
    },
    // Update a set's reps, weight, and/or status
    async updateSet(id, data) {
        ensureSeeded();
        const set = sets.get(id);
        if (!set)
            return null;
        const updated = {
            ...set,
            ...(data.reps !== undefined && { reps: data.reps }),
            ...(data.weight !== undefined && { weight: data.weight }),
            ...(data.status !== undefined && { status: data.status }),
        };
        sets.set(id, updated);
        // Update last values for this exercise when completed
        const exercise = exercises.get(set.exerciseId);
        if (exercise && updated.reps > 0 && updated.status === "complete") {
            exerciseLastValues.set(exercise.name, {
                reps: updated.reps,
                weight: updated.weight,
                updatedAt: new Date(),
            });
        }
        return updated;
    },
    // Create a new set for an exercise
    async createSet(exerciseId, data) {
        ensureSeeded();
        const set = {
            id: generateId("set"),
            exerciseId,
            reps: data.reps,
            weight: data.weight,
            order: data.order,
            status: "todo",
        };
        sets.set(set.id, set);
        return set.id;
    },
    // Delete a set
    async deleteSet(id) {
        ensureSeeded();
        sets.delete(id);
    },
    // Get last recorded values for an exercise by name
    async getLastValuesForExercise(exerciseName) {
        ensureSeeded();
        const lastValues = exerciseLastValues.get(exerciseName);
        if (!lastValues)
            return null;
        return {
            reps: lastValues.reps,
            weight: lastValues.weight,
        };
    },
    // Add exercise to existing session
    async addExerciseToSession(sessionId, data) {
        ensureSeeded();
        const session = sessions.get(sessionId);
        if (!session)
            return null;
        // Get the next order number
        const existingExercises = Array.from(exercises.values()).filter((ex) => ex.sessionId === sessionId);
        const nextOrder = existingExercises.length + 1;
        const exercise = {
            id: generateId("exercise"),
            sessionId,
            name: data.name,
            muscleGroup: data.muscleGroup,
            order: nextOrder,
        };
        exercises.set(exercise.id, exercise);
        const exerciseSets = data.sets.map((setData) => {
            const set = {
                id: generateId("set"),
                exerciseId: exercise.id,
                reps: setData.reps,
                weight: setData.weight,
                order: setData.order,
                status: "todo",
            };
            sets.set(set.id, set);
            return set;
        });
        return {
            ...exercise,
            sets: exerciseSets,
        };
    },
};
