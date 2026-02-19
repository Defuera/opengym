"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.workoutRepositoryInMemory = exports.workoutRepository = void 0;
// Central export for all repositories
// Default to Convex-backed implementation
var workout_repository_convex_1 = require("./workout-repository-convex");
Object.defineProperty(exports, "workoutRepository", { enumerable: true, get: function () { return workout_repository_convex_1.workoutRepository; } });
// Alternative implementations available for testing/development
var workout_repository_1 = require("./workout-repository");
Object.defineProperty(exports, "workoutRepositoryInMemory", { enumerable: true, get: function () { return workout_repository_1.workoutRepository; } });
