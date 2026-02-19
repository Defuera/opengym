// Core domain types used by repositories

export type User = {
  id: string;
  name: string;
  createdAt: Date;
  unit?: "metric" | "imperial";
};

export type Session = {
  id: string;
  userId: string;
  date: Date;
  status: "planned" | "active" | "completed";
  createdAt: Date;
  updatedAt: Date;
};

export type Exercise = {
  id: string;
  sessionId: string;
  name: string;
  muscleGroup: string;
  order: number;
};

export type Set = {
  id: string;
  exerciseId: string;
  reps: number;
  weight: number;
  order: number;
  status: "todo" | "later" | "complete";
};

export type SessionWithExercisesAndSets = Session & {
  exercises: (Exercise & {
    sets: Set[];
  })[];
};

export type Analytics = {
  lastSession: {
    id: string;
    date: number;
    exercises: string[];
    volume: number;
    comparison: {
      current: number;
      previous: number;
      percentChange: number;
    } | null;
  } | null;
  currentWeek: {
    sessionCount: number;
    totalVolume: number;
  };
  lastWeek: {
    sessionCount: number;
    totalVolume: number;
  };
  weeklyTrend: Array<{
    week: number;
    volume: number;
    sessionCount: number;
  }>;
};

export type ExerciseAnalytics = {
  name: string;
  muscleGroup: string;
  lastWeight: number;
  trend: "up" | "down" | "stable";
  sessionCount: number;
};

export type ExerciseDetail = {
  personalRecords: {
    maxWeight: number;
    maxVolumeSession: {
      volume: number;
      date: number;
    };
    maxRepsAtHeaviestWeight: {
      reps: number;
      weight: number;
    };
  };
  weightProgression: Array<{
    date: number;
    weight: number;
  }>;
  volumePerSession: Array<{
    date: number;
    volume: number;
  }>;
  sessionHistory: Array<{
    sessionId: string;
    date: number;
    sets: Array<{
      reps: number;
      weight: number;
    }>;
  }>;
};
