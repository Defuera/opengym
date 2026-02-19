import Link from "next/link";
import { workoutRepository } from "@/lib/repositories";
import StartSessionButton from "./start-session-button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { formatWeight } from "@/lib/units";
export const dynamic = 'force-dynamic';

type SessionWithExercisesAndSets = {
  id: string;
  date: Date;
  status: string;
  exercises: {
    id: string;
    name: string;
    sets: {
      reps: number;
      weight: number;
    }[];
  }[];
};


export default async function Home() {
  const sessions = await workoutRepository.listRecentSessionsForUser("default-user", 10);
  const user = await workoutRepository.getUser("default-user");
  const unit = user?.unit ?? "metric";
  const aiEnabled = process.env.NEXT_PUBLIC_AI_ENABLED === "true";

  return (
    <div className="flex min-h-screen flex-col bg-zinc-50 dark:bg-zinc-950">
      <header className="sticky top-0 z-10 border-b bg-white/80 backdrop-blur-lg px-4 py-4 dark:bg-zinc-900/80">
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-bold text-zinc-900 dark:text-zinc-50">
            OpenGym
          </h1>
          <div className="flex items-center gap-3">
            {aiEnabled && (
              <Link
                href="/coach"
                className="text-zinc-600 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-50 text-sm font-medium"
              >
                Ask Coach
              </Link>
            )}
            <Link
              href="/settings"
              className="text-zinc-600 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-50 text-sm font-medium"
            >
              Settings
            </Link>
          </div>
        </div>
      </header>

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
                    Start your first workout below
                  </p>
                </CardContent>
              </Card>
            ) : (
              <div className="space-y-4">
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
                      key={session.id}
                      href={
                        session.status === "active"
                          ? `/session/${session.id}`
                          : `/session/${session.id}/summary`
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

      <div className="fixed bottom-0 left-0 right-0 border-t bg-white/95 backdrop-blur-lg p-4 dark:bg-zinc-900/95">
        <div className="mx-auto max-w-2xl">
          <StartSessionButton />
        </div>
      </div>
    </div>
  );
}
