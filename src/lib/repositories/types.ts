// Core domain types used by repositories

export type User = {
  id: string;
  name: string;
  createdAt: Date;
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
};

export type SessionWithExercisesAndSets = Session & {
  exercises: (Exercise & {
    sets: Set[];
  })[];
};
