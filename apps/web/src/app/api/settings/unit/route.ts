import { workoutRepository } from "@/lib/repositories";
import { NextRequest, NextResponse } from "next/server";

export async function PATCH(req: NextRequest) {
  try {
    const body = await req.json();
    const { unit } = body;

    if (unit !== "metric" && unit !== "imperial") {
      return NextResponse.json(
        { error: "Invalid unit. Must be 'metric' or 'imperial'" },
        { status: 400 }
      );
    }

    await workoutRepository.updateUserUnit("default-user", unit);

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error("Error updating unit preference:", error);
    return NextResponse.json(
      { error: "Failed to update unit preference" },
      { status: 500 }
    );
  }
}
