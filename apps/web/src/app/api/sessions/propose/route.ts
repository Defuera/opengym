import { NextRequest, NextResponse } from "next/server";
import { workoutRepository } from "@/lib/repositories";
import { proposeSession } from "@/lib/session-proposer";
import { ConvexHttpClient } from "convex/browser";
import { api } from "../../../../../convex/_generated/api";
import type { Id } from "../../../../../convex/_generated/dataModel";

const AI_ENABLED = process.env.NEXT_PUBLIC_AI_ENABLED === "true";
const CONVEX_URL = process.env.NEXT_PUBLIC_CONVEX_URL;

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { userId = "default-user", goal } = body;

    // Use AI planner if enabled and properly configured
    if (AI_ENABLED && CONVEX_URL) {
      try {
        const convexClient = new ConvexHttpClient(CONVEX_URL);

        // Call Convex action to plan and create session with AI
        const result = await convexClient.action(
          api.aiSessionPlanner.planAndCreateSession,
          {
            userId: userId as Id<"users">,
            goal: goal ?? "general",
          }
        );

        // Fetch the created session to return in standard format
        const session = await workoutRepository.getSessionWithDetails(
          result.sessionId as string
        );

        return NextResponse.json(session, { status: 201 });
      } catch (aiError) {
        console.error("AI planner failed, falling back to rule-based:", aiError);
        // Fall through to rule-based approach
      }
    }

    // Fallback: use rule-based proposal
    const proposal = await proposeSession(userId);

    // Create the session with proposed exercises
    const session = await workoutRepository.createSession({
      userId,
      status: "active",
      exercises: proposal.exercises,
    });

    return NextResponse.json(session, { status: 201 });
  } catch (error) {
    console.error("Failed to propose session:", error);
    return NextResponse.json(
      { error: "Failed to propose session" },
      { status: 500 }
    );
  }
}
