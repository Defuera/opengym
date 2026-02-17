import { NextRequest, NextResponse } from "next/server";
import { workoutRepository } from "@/lib/repositories";

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const body = await request.json();
    const { reps, weight } = body;

    const set = await workoutRepository.updateSet(id, {
      ...(reps !== undefined && { reps }),
      ...(weight !== undefined && { weight }),
    });

    if (!set) {
      return NextResponse.json(
        { error: "Set not found" },
        { status: 404 }
      );
    }

    return NextResponse.json(set);
  } catch (error) {
    console.error("Failed to update set:", error);
    return NextResponse.json(
      { error: "Failed to update set" },
      { status: 500 }
    );
  }
}
