"use client";

import Link from "next/link";
import { useQuery } from "convex/react";
import { api } from "../../../convex/_generated/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { formatWeight } from "@/lib/units";
import { Id } from "../../../convex/_generated/dataModel";

type SessionWithExercisesAndSets = {
  _id: Id<"sessions">;
  date: number;
  status: string;
  exercises: {
    _id: Id<"exercises">;
    name: string;
    sets: {
      reps: number;
      weight: number;
    }[];
  }[];
};


export default function HistoryPage() {
  const user = useQuery(api.users.getDefaultUser, {});
  const sessions = useQuery(
    api.sessions.listWithDetails,
    user ? { userId: user._id, limit: 10 } : "skip"
  );

  const unit = user?.unit ?? "metric";

  // Show loading state while data is being fetched
  if (user === undefined || sessions === undefined) {
    return (
      <div className="flex min-h-screen flex-col bg-zinc-50 dark:bg-zinc-950">
        <main className="flex-1 px-4 pb-24">
          <div className="mx-auto max-w-2xl space-y-6 pt-6">
            <div>
              <h2 className="mb-4 text-lg font-semibold text-zinc-900 dark:text-zinc-50">
                Recent Sessions
              </h2>
              <Card className="text-center py-12">
                <CardContent className="pt-6">
                  <p className="text-zinc-600 dark:text-zinc-400">
                    Loading...
                  </p>
                </CardContent>
              </Card>
            </div>
          </div>
        </main>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen flex-col bg-zinc-50 dark:bg-zinc-950">
      <main className="flex-1 px-4 pb-24">
        <div className="mx-auto max-w-2xl space-y-6 pt-6">
          <div>
            <h2 className="mb-4 text-lg font-semibold text-zinc-900 dark:text-zinc-50">
              Recent Sessions
            </h2>

            {sessions.length === 0 ? (
              <Card className="text-center py-12">
                <CardContent className="pt-6">
                  <p className="text-zinc-600 dark:text-zinc-400 mb-2">
                    No sessions yet
                  </p>
                  <p className="text-sm text-zinc-500 dark:text-zinc-500">
                    Start your first workout using the button below
                  </p>
                </CardContent>
              </Card>
            ) : (
              <div className="flex flex-col gap-4">
                {sessions.map((session: SessionWithExercisesAndSets) => {
                  type ExerciseWithSets = SessionWithExercisesAndSets["exercises"][number];
                  type SetWithFields = ExerciseWithSets["sets"][number];

                  const totalSets = session.exercises.reduce(
                    (acc: number, ex: ExerciseWithSets) => acc + ex.sets.length,
                    0
                  );
                  const totalVolume = session.exercises.reduce(
                    (acc: number, ex: ExerciseWithSets) =>
                      acc +
                      ex.sets.reduce(
                        (setAcc: number, set: SetWithFields) =>
                          setAcc + set.reps * set.weight,
                        0
                      ),
                    0
                  );

                  return (
                    <Link
                      key={session._id}
                      href={
                        session.status === "active"
                          ? `/session/${session._id}`
                          : `/session/${session._id}/summary`
                      }
                    >
                      <Card className="transition-all active:scale-[0.98] hover:shadow-md">
                        <CardHeader className="pb-3">
                          <div className="flex items-center justify-between">
                            <CardTitle className="text-base font-semibold">
                              {new Date(session.date).toLocaleDateString(
                                "en-US",
                                {
                                  weekday: "short",
                                  month: "short",
                                  day: "numeric",
                                }
                              )}
                            </CardTitle>
                            {session.status === "active" && (
                              <Badge variant="default" className="bg-green-600">
                                Active
                              </Badge>
                            )}
                          </div>
                        </CardHeader>
                        <CardContent className="pt-0">
                          <div className="flex gap-4 text-sm text-muted-foreground">
                            <span>{session.exercises.length} exercises</span>
                            <span>·</span>
                            <span>{totalSets} sets</span>
                            {totalVolume > 0 && (
                              <>
                                <span>·</span>
                                <span className="font-medium text-foreground">
                                  {formatWeight(totalVolume, unit)}
                                </span>
                              </>
                            )}
                          </div>
                        </CardContent>
                      </Card>
                    </Link>
                  );
                })}
              </div>
            )}
          </div>
        </div>
      </main>
    </div>
  );
}
