import { NextRequest, NextResponse } from "next/server";
import { workoutRepository } from "@/lib/repositories";

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id: exerciseId } = await params;
    const body = await request.json();
    const { reps, weight, order } = body;

    const setId = await workoutRepository.createSet(exerciseId, {
      reps,
      weight,
      order,
    });

    return NextResponse.json({ id: setId });
  } catch (error) {
    console.error("Failed to create set:", error);
    return NextResponse.json(
      { error: "Failed to create set" },
      { status: 500 }
    );
  }
}
