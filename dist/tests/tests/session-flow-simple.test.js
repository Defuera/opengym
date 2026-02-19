"use strict";
// Simple integration test for session flow without test framework dependencies
// This exercises the repository API directly and verifies Convex persistence
Object.defineProperty(exports, "__esModule", { value: true });
const repositories_1 = require("../src/lib/repositories");
// Simple assertion helpers
function assert(condition, message) {
    if (!condition) {
        throw new Error(`Assertion failed: ${message}`);
    }
}
function assertEqual(actual, expected, message) {
    if (actual !== expected) {
        throw new Error(`Assertion failed: ${message}\n  Expected: ${expected}\n  Actual: ${actual}`);
    }
}
function assertDefined(value, message) {
    if (value === null || value === undefined) {
        throw new Error(`Assertion failed: ${message} - value is ${value}`);
    }
}
// Test state
const DEFAULT_USER_ID = "default-user";
let sessionId;
let exerciseId;
let setId;
async function testCreateSession() {
    console.log("  → Creating new session with exercises and sets...");
    const session = await repositories_1.workoutRepository.createSession({
        userId: DEFAULT_USER_ID,
        status: "active",
        exercises: [
            {
                name: "Bench Press",
                muscleGroup: "chest",
                order: 1,
                sets: [
                    { reps: 10, weight: 135, order: 1 },
                    { reps: 8, weight: 155, order: 2 },
                    { reps: 6, weight: 185, order: 3 },
                ],
            },
        ],
    });
    assertDefined(session, "Session should be created");
    assert(session.id.length > 0, "Session should have an ID");
    assertEqual(session.status, "active", "Session status should be active");
    assertEqual(session.exercises.length, 1, "Session should have 1 exercise");
    assertEqual(session.exercises[0].name, "Bench Press", "Exercise name should be Bench Press");
    assertEqual(session.exercises[0].sets.length, 3, "Exercise should have 3 sets");
    assertEqual(session.exercises[0].sets[0].status, "todo", "Initial set status should be todo");
    assertEqual(session.exercises[0].sets[0].reps, 10, "First set should have 10 reps");
    assertEqual(session.exercises[0].sets[0].weight, 135, "First set should have 135 weight");
    // Store IDs for later tests
    sessionId = session.id;
    exerciseId = session.exercises[0].id;
    setId = session.exercises[0].sets[0].id;
    console.log(`    ✓ Session created: ${sessionId}`);
}
async function testCompleteSet() {
    console.log("  → Completing set with updated reps and weight...");
    const updatedSet = await repositories_1.workoutRepository.updateSet(setId, {
        reps: 12,
        weight: 145,
        status: "complete",
    });
    assertDefined(updatedSet, "Updated set should be returned");
    assertEqual(updatedSet.status, "complete", "Set status should be complete");
    console.log("    ✓ Set completed");
}
async function testPersistence() {
    console.log("  → Verifying set completion persisted to Convex...");
    // Small delay to ensure Convex has propagated the update
    await new Promise((resolve) => setTimeout(resolve, 100));
    const session = await repositories_1.workoutRepository.getSessionWithDetails(sessionId);
    assertDefined(session, "Session should be retrieved");
    assertEqual(session.exercises.length, 1, "Session should still have 1 exercise");
    assertEqual(session.exercises[0].sets.length, 3, "Exercise should still have 3 sets");
    const firstSet = session.exercises[0].sets[0];
    assertEqual(firstSet.id, setId, "First set ID should match");
    assertEqual(firstSet.status, "complete", "First set status should be complete");
    assertEqual(firstSet.reps, 12, "First set should have updated reps (12)");
    assertEqual(firstSet.weight, 145, "First set should have updated weight (145)");
    assertEqual(session.exercises[0].sets[1].status, "todo", "Second set should still be todo");
    assertEqual(session.exercises[0].sets[2].status, "todo", "Third set should still be todo");
    console.log("    ✓ Set completion persisted correctly");
}
async function testCompleteAdditionalSets() {
    console.log("  → Completing additional sets...");
    const session = await repositories_1.workoutRepository.getSessionWithDetails(sessionId);
    assertDefined(session, "Session should be retrieved");
    const secondSetId = session.exercises[0].sets[1].id;
    await repositories_1.workoutRepository.updateSet(secondSetId, {
        reps: 10,
        weight: 155,
        status: "complete",
    });
    const thirdSetId = session.exercises[0].sets[2].id;
    await repositories_1.workoutRepository.updateSet(thirdSetId, {
        reps: 8,
        weight: 185,
        status: "complete",
    });
    // Small delay for Convex propagation
    await new Promise((resolve) => setTimeout(resolve, 100));
    const updatedSession = await repositories_1.workoutRepository.getSessionWithDetails(sessionId);
    assertDefined(updatedSession, "Updated session should be retrieved");
    assertEqual(updatedSession.exercises[0].sets[0].status, "complete", "First set should be complete");
    assertEqual(updatedSession.exercises[0].sets[1].status, "complete", "Second set should be complete");
    assertEqual(updatedSession.exercises[0].sets[2].status, "complete", "Third set should be complete");
    console.log("    ✓ All sets completed");
}
async function testLastValues() {
    console.log("  → Testing last-used reps/weight for exercise...");
    // Small delay to ensure Convex has indexed the completed sets
    await new Promise((resolve) => setTimeout(resolve, 200));
    const lastValues = await repositories_1.workoutRepository.getLastValuesForExercise("Bench Press");
    assertDefined(lastValues, "Last values should be returned");
    assert(lastValues.reps > 0, "Last values should have reps greater than 0");
    assert(lastValues.weight > 0, "Last values should have weight greater than 0");
    console.log(`    ✓ Last values retrieved: ${lastValues.reps} reps @ ${lastValues.weight} lbs`);
}
async function testAddExercise() {
    console.log("  → Adding new exercise to session...");
    const newExerciseId = await repositories_1.workoutRepository.addExerciseToSession(sessionId, {
        name: "Overhead Press",
        muscleGroup: "shoulders",
        sets: [
            { reps: 10, weight: 95, order: 1 },
            { reps: 8, weight: 115, order: 2 },
        ],
    });
    assert(newExerciseId.length > 0, "New exercise ID should be returned");
    // Small delay for Convex propagation
    await new Promise((resolve) => setTimeout(resolve, 100));
    const session = await repositories_1.workoutRepository.getSessionWithDetails(sessionId);
    assertDefined(session, "Session should be retrieved");
    assertEqual(session.exercises.length, 2, "Session should now have 2 exercises");
    assertEqual(session.exercises[1].name, "Overhead Press", "Second exercise should be Overhead Press");
    assertEqual(session.exercises[1].sets.length, 2, "Second exercise should have 2 sets");
    console.log("    ✓ Exercise added successfully");
}
async function testCompleteSession() {
    console.log("  → Completing session...");
    const updatedSession = await repositories_1.workoutRepository.updateSessionStatus(sessionId, "completed");
    assertDefined(updatedSession, "Updated session should be returned");
    assertEqual(updatedSession.status, "completed", "Session status should be completed");
    // Small delay for Convex propagation
    await new Promise((resolve) => setTimeout(resolve, 100));
    const session = await repositories_1.workoutRepository.getSessionWithDetails(sessionId);
    assertDefined(session, "Session should be retrieved");
    assertEqual(session.status, "completed", "Session status should be persisted as completed");
    console.log("    ✓ Session completed");
}
async function testListSessions() {
    console.log("  → Listing recent sessions...");
    const sessions = await repositories_1.workoutRepository.listRecentSessionsForUser(DEFAULT_USER_ID, 10);
    assertDefined(sessions, "Sessions should be returned");
    assert(sessions.length > 0, "Should have at least one session");
    const newSession = sessions.find((s) => s.id === sessionId);
    assertDefined(newSession, "New session should be in the list");
    assertEqual(newSession.status, "completed", "Session status should be completed");
    assertEqual(newSession.exercises.length, 2, "Session should have 2 exercises");
    console.log(`    ✓ Found ${sessions.length} sessions`);
}
async function testGetCompletedSessions() {
    console.log("  → Retrieving completed sessions...");
    const completedSessions = await repositories_1.workoutRepository.getRecentCompletedSessions(DEFAULT_USER_ID, 5);
    assertDefined(completedSessions, "Completed sessions should be returned");
    assert(completedSessions.length > 0, "Should have at least one completed session");
    completedSessions.forEach((session) => {
        assertEqual(session.status, "completed", "All sessions should be completed");
    });
    const newSession = completedSessions.find((s) => s.id === sessionId);
    assertDefined(newSession, "New session should be in completed sessions");
    console.log(`    ✓ Found ${completedSessions.length} completed sessions`);
}
async function testCreateAndDeleteSet() {
    console.log("  → Testing create and delete set...");
    const session = await repositories_1.workoutRepository.getSessionWithDetails(sessionId);
    assertDefined(session, "Session should be retrieved");
    const firstExerciseId = session.exercises[0].id;
    const initialSetCount = session.exercises[0].sets.length;
    const newSetId = await repositories_1.workoutRepository.createSet(firstExerciseId, {
        reps: 5,
        weight: 205,
        order: initialSetCount + 1,
    });
    assert(newSetId.length > 0, "New set ID should be returned");
    // Small delay for Convex propagation
    await new Promise((resolve) => setTimeout(resolve, 100));
    let updatedSession = await repositories_1.workoutRepository.getSessionWithDetails(sessionId);
    assertDefined(updatedSession, "Updated session should be retrieved");
    assertEqual(updatedSession.exercises[0].sets.length, initialSetCount + 1, "Set count should increase by 1");
    await repositories_1.workoutRepository.deleteSet(newSetId);
    // Small delay for Convex propagation
    await new Promise((resolve) => setTimeout(resolve, 100));
    const finalSession = await repositories_1.workoutRepository.getSessionWithDetails(sessionId);
    assertDefined(finalSession, "Final session should be retrieved");
    assertEqual(finalSession.exercises[0].sets.length, initialSetCount, "Set count should return to original");
    console.log("    ✓ Create and delete set successful");
}
// Run all tests
async function main() {
    console.log("Running Session Flow Integration Tests\n");
    try {
        await testCreateSession();
        await testCompleteSet();
        await testPersistence();
        await testCompleteAdditionalSets();
        await testLastValues();
        await testAddExercise();
        await testCompleteSession();
        await testListSessions();
        await testGetCompletedSessions();
        await testCreateAndDeleteSet();
    }
    catch (error) {
        console.error("\n❌ Test failed:");
        throw error;
    }
}
// Execute tests
main();
