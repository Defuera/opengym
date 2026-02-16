import { prisma } from "@/lib/prisma";
import { notFound } from "next/navigation";
import SessionView from "./session-view";
export const dynamic = 'force-dynamic';

export default async function SessionPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;

  const session = await prisma.session.findUnique({
    where: { id },
    include: {
      exercises: {
        include: {
          sets: {
            orderBy: {
              order: "asc",
            },
          },
        },
        orderBy: {
          order: "asc",
        },
      },
    },
  });

  if (!session) {
    notFound();
  }

  return <SessionView session={session} />;
}
