import { NextRequest, NextResponse } from "next/server";
import { workoutRepository } from "@/lib/repositories";

export async function GET(request: NextRequest) {
  try {
    const searchParams = request.nextUrl.searchParams;
    const exerciseName = searchParams.get("name");

    if (!exerciseName) {
      return NextResponse.json(
        { error: "Exercise name is required" },
        { status: 400 }
      );
    }

    const lastValues = await workoutRepository.getLastValuesForExercise(
      exerciseName
    );

    if (!lastValues) {
      // Return default values if no history
      return NextResponse.json({ reps: 8, weight: 40 });
    }

    return NextResponse.json(lastValues);
  } catch (error) {
    console.error("Failed to get last values:", error);
    return NextResponse.json(
      { error: "Failed to get last values" },
      { status: 500 }
    );
  }
}
