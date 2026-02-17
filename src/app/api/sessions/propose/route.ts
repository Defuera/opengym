import { NextRequest, NextResponse } from "next/server";
import { workoutRepository } from "@/lib/repositories";
import { proposeSession } from "@/lib/session-proposer";

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { userId = "default-user" } = body;

    // Generate proposed exercises based on history
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
