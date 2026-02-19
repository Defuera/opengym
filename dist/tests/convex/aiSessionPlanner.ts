import { v } from "convex/values";
import { action } from "./_generated/server";
import { api } from "./_generated/api";
import { Id } from "./_generated/dataModel";

/**
 * AI-powered session planning action.
 * Fetches user context, calls the AI planner via Node.js runtime,
 * and creates a session with the proposed exercises.
 */
export const planAndCreateSession = action({
  args: {
    userId: v.id("users"),
    goal: v.optional(
      v.union(
        v.literal("strength"),
        v.literal("hypertrophy"),
        v.literal("fat_loss"),
        v.literal("general"),
        v.literal("rehab")
      )
    ),
  },
  handler: async (ctx, args) => {
    const goal = args.goal ?? "general";

    // Fetch user context via query
    const userContext = await ctx.runQuery(api.aiUserContext.getUserContext, {
      userId: args.userId,
      sessionLimit: 5,
    });

    // Prepare input for AI planner
    const planInput = {
      userId: args.userId as string,
      goal,
      currentSessionId: null,
      recentSessions: userContext.recentSessions,
      memories: userContext.aiMemories,
    };

    // Call AI planner - this will run in Node.js environment
    // We'll use a dynamic import to load the server-side module
    const { getAI } = await import("../src/lib/ai");
    const ai = getAI();
    const sessionPlan = await ai.planner.proposeSessionPlan(planInput);

    // Convert AI plan to database format
    // AI returns exerciseId (exercise name) and sets with target values
    const exercises = sessionPlan.exercises.map((planEx, index) => ({
      name: planEx.exerciseId, // exerciseId is actually the exercise name
      muscleGroup: inferMuscleGroup(planEx.exerciseId),
      order: index + 1,
      sets: planEx.sets.map((set, setIndex) => ({
        reps: set.targetReps || 0,
        weight: set.targetWeight || 0,
        order: setIndex + 1,
      })),
    }));

    // Create session via mutation
    const sessionId: Id<"sessions"> = await ctx.runMutation(api.sessions.create, {
      userId: args.userId,
      status: "active",
      exercises,
    });

    return {
      sessionId: sessionId as string,
      plan: sessionPlan,
    };
  },
});

/**
 * Simple muscle group inference based on exercise name.
 * This is a fallback - ideally we'd have an exercise database.
 */
function inferMuscleGroup(exerciseName: string): string {
  const name = exerciseName.toLowerCase();

  if (
    name.includes("bench") ||
    name.includes("press") && name.includes("chest") ||
    name.includes("fly")
  ) {
    return "chest";
  }

  if (name.includes("pull") || name.includes("row") || name.includes("lat")) {
    return "back";
  }

  if (
    name.includes("squat") ||
    name.includes("leg") ||
    name.includes("lunge") ||
    name.includes("deadlift")
  ) {
    return "legs";
  }

  if (
    name.includes("shoulder") ||
    (name.includes("press") && !name.includes("bench"))
  ) {
    return "shoulders";
  }

  if (name.includes("curl") || name.includes("bicep")) {
    return "biceps";
  }

  if (name.includes("tricep") || name.includes("dip")) {
    return "triceps";
  }

  return "other";
}
