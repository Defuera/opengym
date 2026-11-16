import { NextRequest, NextResponse } from "next/server";
import { workoutRepository } from "@/lib/repositories";

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const body = await request.json();

    const { name, muscleGroup, sets } = body;

    if (!name || !muscleGroup || !sets || !Array.isArray(sets)) {
      return NextResponse.json(
        { error: "Invalid request body" },
        { status: 400 }
      );
    }

    const exerciseId = await workoutRepository.addExerciseToSession(id, {
      name,
      muscleGroup,
      sets,
    });

    return NextResponse.json({ id: exerciseId }, { status: 201 });
  } catch (error) {
    console.error("Error adding exercise to session:", error);
    return NextResponse.json(
      { error: "Failed to add exercise" },
      { status: 500 }
    );
  }
}
