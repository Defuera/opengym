import { NextRequest, NextResponse } from "next/server";
import { revalidatePath } from "next/cache";
import { workoutRepository } from "@/lib/repositories";

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const body = await request.json();
    const { reps, weight, status, sessionId } = body;

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

    // Revalidate the session page if sessionId is provided
    if (sessionId) {
      revalidatePath(`/session/${sessionId}`);
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
    const url = new URL(request.url);
    const sessionId = url.searchParams.get("sessionId");

    await workoutRepository.deleteSet(id);

    // Revalidate the session page if sessionId is provided
    if (sessionId) {
      revalidatePath(`/session/${sessionId}`);
    }

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error("Failed to delete set:", error);
    return NextResponse.json(
      { error: "Failed to delete set" },
      { status: 500 }
    );
  }
}
