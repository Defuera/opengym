import { workoutRepository } from "@/lib/repositories";
import { notFound } from "next/navigation";
import SessionView from "./session-view";
export const dynamic = 'force-dynamic';

export default async function SessionPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;

  const session = await workoutRepository.getSessionWithDetails(id);

  if (!session) {
    notFound();
  }

  const user = await workoutRepository.getUser("default-user");
  const unit = user?.unit ?? "metric";

  return <SessionView session={session} unit={unit} />;
}
