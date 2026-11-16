"use server";

import { getAI } from "@/lib/ai";
import type { SessionPlanInput, SessionPlan } from "@/lib/ai/types";
import type { ConvexHttpClient } from "convex/browser";
import { api } from "../../convex/_generated/api";
import type { Id } from "../../convex/_generated/dataModel";

export interface PlanSessionOptions {
  userId: Id<"users">;
  goal?: "strength" | "hypertrophy" | "fat_loss" | "general" | "rehab";
  convexClient: ConvexHttpClient;
}

/**
 * Server-side helper that orchestrates AI session planning.
 * Fetches user context from Convex, calls the AI planner, and returns a plan.
 */
export async function planSessionForUser(
  options: PlanSessionOptions
): Promise<SessionPlan> {
  const { userId, goal = "general", convexClient } = options;

  // Fetch user context (profile, recent sessions, memories)
  const userContext = await convexClient.query(api.aiUserContext.getUserContext, {
    userId,
    sessionLimit: 5,
  });

  // Map to SessionPlanInput format
  const planInput: SessionPlanInput = {
    userId: userId as string,
    goal,
    currentSessionId: null,
    recentSessions: userContext.recentSessions,
    memories: userContext.aiMemories,
  };

  // Call AI planner
  const ai = getAI();
  const sessionPlan = await ai.planner.proposeSessionPlan(planInput);

  return sessionPlan;
}
