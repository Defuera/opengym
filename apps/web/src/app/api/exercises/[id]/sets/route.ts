import { NextRequest, NextResponse } from "next/server";
import { revalidatePath } from "next/cache";
import { workoutRepository } from "@/lib/repositories";

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id: exerciseId } = await params;
    const body = await request.json();
    const { reps, weight, order, sessionId } = body;

    const setId = await workoutRepository.createSet(exerciseId, {
      reps,
      weight,
      order,
    });

    // Revalidate the session page if sessionId is provided
    if (sessionId) {
      revalidatePath(`/session/${sessionId}`);
    }

    return NextResponse.json({ id: setId });
  } catch (error) {
    console.error("Failed to create set:", error);
    return NextResponse.json(
      { error: "Failed to create set" },
      { status: 500 }
    );
  }
}
