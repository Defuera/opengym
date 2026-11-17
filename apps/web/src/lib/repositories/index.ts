// Central export for all repositories
// Default to Convex-backed implementation
export { workoutRepository } from "./workout-repository-convex";

// Alternative implementations available for testing/development
export { workoutRepository as workoutRepositoryInMemory } from "./workout-repository";

export type * from "./types";
