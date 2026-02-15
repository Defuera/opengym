import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { proposeSession } from "@/lib/session-proposer";

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { userId = "default-user" } = body;

    // Generate proposed exercises based on history
    const proposal = await proposeSession(userId);

    // Create the session with proposed exercises
    const session = await prisma.session.create({
      data: {
        userId,
        status: "active",
        exercises: {
          create: proposal.exercises.map((ex) => ({
            name: ex.name,
            muscleGroup: ex.muscleGroup,
            order: ex.order,
            sets: {
              create: ex.sets,
            },
          })),
        },
      },
      include: {
        exercises: {
          include: {
            sets: true,
          },
          orderBy: {
            order: "asc",
          },
        },
      },
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
