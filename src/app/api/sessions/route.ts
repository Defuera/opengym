import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { userId = "default-user", exercises } = body;

    const session = await prisma.session.create({
      data: {
        userId,
        status: "active",
        exercises: exercises
          ? {
              create: exercises.map(
                (ex: { name: string; muscleGroup: string }, index: number) => ({
                  name: ex.name,
                  muscleGroup: ex.muscleGroup,
                  order: index,
                  sets: {
                    create: [
                      { reps: 0, weight: 0, order: 1 },
                      { reps: 0, weight: 0, order: 2 },
                      { reps: 0, weight: 0, order: 3 },
                    ],
                  },
                })
              ),
            }
          : undefined,
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
    console.error("Failed to create session:", error);
    return NextResponse.json(
      { error: "Failed to create session" },
      { status: 500 }
    );
  }
}
