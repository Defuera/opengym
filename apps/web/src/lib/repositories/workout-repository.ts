// In-memory workout repository
// Stores sessions, exercises, and sets in module-level maps

import type {
  User,
  Session,
  Exercise,
  Set,
  SessionWithExercisesAndSets,
} from "./types";

// Module-level storage
const users = new Map<string, User>();
const sessions = new Map<string, Session>();
const exercises = new Map<string, Exercise>();
const sets = new Map<string, Set>();

// Track last values per exercise name (for prefilling)
type ExerciseLastValues = {
  reps: number;
  weight: number;
  updatedAt: Date;
};
const exerciseLastValues = new Map<string, ExerciseLastValues>();

// ID generator
let idCounter = 0;
function generateId(prefix: string): string {
  return `${prefix}_${Date.now()}_${++idCounter}`;
}

// Seed initial data on first access
let seeded = false;
function ensureSeeded() {
  if (seeded) return;
  seeded = true;

  // Create default user
  const defaultUser: User = {
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
  const session1: Session = {
    id: generateId("session"),
    userId: "default-user",
    date: twoDaysAgo,
    status: "completed",
    createdAt: twoDaysAgo,
    updatedAt: twoDaysAgo,
  };
  sessions.set(session1.id, session1);

  const ex1: Exercise = {
    id: generateId("exercise"),
    sessionId: session1.id,
    name: "Bench Press",
    muscleGroup: "chest",
    order: 1,
  };
  exercises.set(ex1.id, ex1);

  const ex2: Exercise = {
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
    const set: Set = {
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
    const set: Set = {
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
  const session2: Session = {
    id: generateId("session"),
    userId: "default-user",
    date: yesterday,
    status: "completed",
    createdAt: yesterday,
    updatedAt: yesterday,
  };
  sessions.set(session2.id, session2);

  const ex3: Exercise = {
    id: generateId("exercise"),
    sessionId: session2.id,
    name: "Pull-ups",
    muscleGroup: "back",
    order: 1,
  };
  exercises.set(ex3.id, ex3);

  const ex4: Exercise = {
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
    const set: Set = {
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
    const set: Set = {
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
export const workoutRepository = {
  // List recent sessions for a user
  async listRecentSessionsForUser(
    userId: string,
    limit: number = 10
  ): Promise<SessionWithExercisesAndSets[]> {
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
  async getSessionWithDetails(
    id: string
  ): Promise<SessionWithExercisesAndSets | null> {
    ensureSeeded();

    const session = sessions.get(id);
    if (!session) return null;

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
  async getRecentCompletedSessions(
    userId: string,
    limit: number
  ): Promise<SessionWithExercisesAndSets[]> {
    ensureSeeded();

    const completedSessions = Array.from(sessions.values())
      .filter((s) => s.userId === userId && s.status === "completed")
      .sort((a, b) => b.date.getTime() - a.date.getTime())
      .slice(0, limit);

    return Promise.all(
      completedSessions.map(async (session) => {
        const result = await this.getSessionWithDetails(session.id);
        if (!result) throw new Error(`Session ${session.id} not found`);
        return result;
      })
    );
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
    ensureSeeded();

    const now = new Date();
    const session: Session = {
      id: generateId("session"),
      userId: data.userId,
      date: now,
      status: data.status,
      createdAt: now,
      updatedAt: now,
    };
    sessions.set(session.id, session);

    const exercisesWithSets = data.exercises.map((exData) => {
      const exercise: Exercise = {
        id: generateId("exercise"),
        sessionId: session.id,
        name: exData.name,
        muscleGroup: exData.muscleGroup,
        order: exData.order,
      };
      exercises.set(exercise.id, exercise);

      const exerciseSets = exData.sets.map((setData) => {
        const set: Set = {
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
  async updateSessionStatus(
    id: string,
    status: "planned" | "active" | "completed"
  ): Promise<Session | null> {
    ensureSeeded();

    const session = sessions.get(id);
    if (!session) return null;

    const updated: Session = {
      ...session,
      status,
      updatedAt: new Date(),
    };
    sessions.set(id, updated);
    return updated;
  },

  // Update a set's reps, weight, and/or status
  async updateSet(
    id: string,
    data: { reps?: number; weight?: number; status?: "todo" | "later" | "complete" }
  ): Promise<Set | null> {
    ensureSeeded();

    const set = sets.get(id);
    if (!set) return null;

    const updated: Set = {
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
  async createSet(
    exerciseId: string,
    data: { reps: number; weight: number; order: number }
  ): Promise<string> {
    ensureSeeded();

    const set: Set = {
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
  async deleteSet(id: string): Promise<void> {
    ensureSeeded();
    sets.delete(id);
  },

  // Get last recorded values for an exercise by name
  async getLastValuesForExercise(
    exerciseName: string
  ): Promise<{ reps: number; weight: number } | null> {
    ensureSeeded();

    const lastValues = exerciseLastValues.get(exerciseName);
    if (!lastValues) return null;

    return {
      reps: lastValues.reps,
      weight: lastValues.weight,
    };
  },

  // Add exercise to existing session
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
  ): Promise<Exercise & { sets: Set[] } | null> {
    ensureSeeded();

    const session = sessions.get(sessionId);
    if (!session) return null;

    // Get the next order number
    const existingExercises = Array.from(exercises.values()).filter(
      (ex) => ex.sessionId === sessionId
    );
    const nextOrder = existingExercises.length + 1;

    const exercise: Exercise = {
      id: generateId("exercise"),
      sessionId,
      name: data.name,
      muscleGroup: data.muscleGroup,
      order: nextOrder,
    };
    exercises.set(exercise.id, exercise);

    const exerciseSets = data.sets.map((setData) => {
      const set: Set = {
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
