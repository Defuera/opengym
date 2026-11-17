"use client";

import { useParams } from "next/navigation";
import { useQuery } from "convex/react";
import { api } from "../../../../convex/_generated/api";
import SessionView from "./session-view";

export default function SessionPage() {
  const params = useParams();
  const id = params.id as string;

  const user = useQuery(api.users.getDefaultUser, {});
  const session = useQuery(api.sessions.getWithDetails, { id: id as any });

  if (user === undefined || session === undefined) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-zinc-50 dark:bg-zinc-950">
        <p className="text-zinc-600 dark:text-zinc-400">Loading...</p>
      </div>
    );
  }

  if (!session) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-zinc-50 dark:bg-zinc-950">
        <p className="text-zinc-600 dark:text-zinc-400">Session not found</p>
      </div>
    );
  }

  const unit = user?.unit ?? "metric";

  // Map Convex types (_id/number) to what SessionView expects (id/Date)
  const normalizedSession = {
    ...session,
    id: session._id,
    date: new Date(session.date),
    exercises: session.exercises.map((ex) => ({
      ...ex,
      id: ex._id,
      sets: ex.sets.map((s) => ({
        ...s,
        id: s._id,
        status: (s.status ?? "todo") as "todo" | "later" | "complete",
      })),
    })),
  };

  return <SessionView session={normalizedSession as any} unit={unit} />;
}
