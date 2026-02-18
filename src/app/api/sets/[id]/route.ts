import { NextRequest, NextResponse } from "next/server";
import { workoutRepository } from "@/lib/repositories";

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const body = await request.json();
    const { reps, weight, status } = body;

    const set = await workoutRepository.updateSet(id, {
      ...(reps !== undefined && { reps }),
      ...(weight !== undefined && { weight }),
      ...(status !== undefined && { status }),
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

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;

    await workoutRepository.deleteSet(id);

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error("Failed to delete set:", error);
    return NextResponse.json(
      { error: "Failed to delete set" },
      { status: 500 }
    );
  }
}
