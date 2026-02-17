import { workoutRepository } from "./repositories";

// Exercise templates grouped by workout type
const EXERCISE_TEMPLATES = {
  push: [
    { name: "Bench Press", muscleGroup: "chest" },
    { name: "Incline Dumbbell Press", muscleGroup: "chest" },
    { name: "Overhead Press", muscleGroup: "shoulders" },
    { name: "Tricep Dips", muscleGroup: "triceps" },
  ],
  pull: [
    { name: "Pull-ups", muscleGroup: "back" },
    { name: "Barbell Rows", muscleGroup: "back" },
    { name: "Face Pulls", muscleGroup: "shoulders" },
    { name: "Bicep Curls", muscleGroup: "biceps" },
  ],
  legs: [
    { name: "Squats", muscleGroup: "legs" },
    { name: "Romanian Deadlift", muscleGroup: "legs" },
    { name: "Leg Press", muscleGroup: "legs" },
    { name: "Leg Curls", muscleGroup: "legs" },
  ],
};

// Standard volume per session: 3 sets per exercise
const SETS_PER_EXERCISE = 3;
const DEFAULT_EXERCISES_PER_SESSION = 4;
const HIGH_VOLUME_THRESHOLD = 12; // total sets

type WorkoutType = "push" | "pull" | "legs";

/**
 * Determines workout type based on muscle groups in a session
 */
function categorizeSession(
  exercises: Array<{ muscleGroup: string }>
): WorkoutType {
  const muscleGroups = exercises.map((ex) => ex.muscleGroup.toLowerCase());

  const hasChest = muscleGroups.some((mg) => mg.includes("chest"));
  const hasTriceps = muscleGroups.some((mg) => mg.includes("tricep"));
  const hasShoulders = muscleGroups.some((mg) => mg.includes("shoulder"));

  const hasBack = muscleGroups.some((mg) => mg.includes("back"));
  const hasBiceps = muscleGroups.some((mg) => mg.includes("bicep"));

  const hasLegs = muscleGroups.some((mg) => mg.includes("leg") || mg.includes("quad") || mg.includes("hamstring") || mg.includes("glute"));

  if (hasLegs) return "legs";
  if (hasChest || hasTriceps || (hasShoulders && !hasBack)) return "push";
  return "pull";
}

/**
 * Proposes the next workout type based on recent sessions
 */
async function proposeNextWorkoutType(userId: string): Promise<WorkoutType> {
  const recentSessions = await workoutRepository.getRecentCompletedSessions(
    userId,
    1
  );

  if (recentSessions.length === 0) {
    // No history, start with push
    return "push";
  }

  const lastSessionType = categorizeSession(recentSessions[0].exercises);

  // Simple rotation: push -> pull -> legs -> push
  const rotation: Record<WorkoutType, WorkoutType> = {
    push: "pull",
    pull: "legs",
    legs: "push",
  };

  return rotation[lastSessionType];
}

/**
 * Checks if recent sessions were high volume and adjusts accordingly
 */
async function shouldReduceVolume(userId: string): Promise<boolean> {
  const recentSessions = await workoutRepository.getRecentCompletedSessions(
    userId,
    3
  );

  if (recentSessions.length < 2) {
    return false;
  }

  // Check if all recent sessions were high volume
  const allHighVolume = recentSessions.every((session) => {
    const totalSets = session.exercises.reduce(
      (acc, ex) => acc + ex.sets.length,
      0
    );
    return totalSets >= HIGH_VOLUME_THRESHOLD;
  });

  return allHighVolume;
}

/**
 * Proposes a new workout session based on recent history
 */
export async function proposeSession(userId: string) {
  const workoutType = await proposeNextWorkoutType(userId);
  const reduceVolume = await shouldReduceVolume(userId);

  const exercises = EXERCISE_TEMPLATES[workoutType];
  const exerciseCount = reduceVolume
    ? DEFAULT_EXERCISES_PER_SESSION - 1
    : DEFAULT_EXERCISES_PER_SESSION;

  // Select exercises up to the determined count
  const selectedExercises = exercises.slice(0, exerciseCount);

  return {
    exercises: selectedExercises.map((ex, index) => ({
      name: ex.name,
      muscleGroup: ex.muscleGroup,
      order: index + 1,
      sets: Array.from({ length: SETS_PER_EXERCISE }, (_, setIndex) => ({
        reps: 0,
        weight: 0,
        order: setIndex + 1,
      })),
    })),
  };
}
