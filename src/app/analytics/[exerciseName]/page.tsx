import { workoutRepository } from "@/lib/repositories";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { formatWeight } from "@/lib/units";
import Link from "next/link";
import { WeightProgressionChart, VolumePerSessionChart } from "./exercise-charts";
export const dynamic = 'force-dynamic';

export default async function ExerciseDetailPage({
  params,
}: {
  params: Promise<{ exerciseName: string }>;
}) {
  const { exerciseName } = await params;
  const decodedName = decodeURIComponent(exerciseName);
  const exerciseDetail = await workoutRepository.getExerciseDetail("default-user", decodedName);
  const user = await workoutRepository.getUser("default-user");
  const unit = user?.unit ?? "metric";

  const { personalRecords, weightProgression, volumePerSession, sessionHistory } = exerciseDetail;

  return (
    <div className="flex min-h-screen flex-col bg-zinc-50 dark:bg-zinc-950">
      <header className="sticky top-0 z-10 border-b bg-white/80 backdrop-blur-lg px-4 py-4 dark:bg-zinc-900/80">
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-bold text-zinc-900 dark:text-zinc-50">
            {decodedName}
          </h1>
          <Link
            href="/analytics"
            className="text-zinc-600 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-50 text-sm font-medium"
          >
            Back
          </Link>
        </div>
      </header>

      <main className="flex-1 px-4 pb-24">
        <div className="mx-auto max-w-2xl space-y-6 pt-6">
          {/* Personal Records */}
          <div>
            <h2 className="mb-3 text-lg font-semibold">Personal Records</h2>
            <div className="grid grid-cols-3 gap-2">
              <Card className="bg-gradient-to-br from-blue-500 to-blue-600 text-white">
                <CardContent className="p-3">
                  <p className="text-[10px] opacity-90 mb-1">Heaviest Weight</p>
                  <p className="text-lg font-bold">
                    {formatWeight(personalRecords.maxWeight, unit)}
                  </p>
                </CardContent>
              </Card>

              <Card className="bg-gradient-to-br from-green-500 to-green-600 text-white">
                <CardContent className="p-3">
                  <p className="text-[10px] opacity-90 mb-1">Best Volume</p>
                  <p className="text-lg font-bold">
                    {formatWeight(personalRecords.maxVolumeSession.volume, unit)}
                  </p>
                </CardContent>
              </Card>

              <Card className="bg-gradient-to-br from-purple-500 to-purple-600 text-white">
                <CardContent className="p-3">
                  <p className="text-[10px] opacity-90 mb-1">Best Reps</p>
                  <p className="text-lg font-bold">
                    {personalRecords.maxRepsAtHeaviestWeight.reps}×{formatWeight(personalRecords.maxRepsAtHeaviestWeight.weight, unit)}
                  </p>
                </CardContent>
              </Card>
            </div>
          </div>

          {/* Weight Progression Chart */}
          {weightProgression.length > 0 && (
            <Card>
              <CardHeader>
                <CardTitle className="text-base">Weight Progression</CardTitle>
              </CardHeader>
              <CardContent>
                <WeightProgressionChart data={weightProgression} unit={unit} />
              </CardContent>
            </Card>
          )}

          {/* Volume Per Session Chart */}
          {volumePerSession.length > 0 && (
            <Card>
              <CardHeader>
                <CardTitle className="text-base">Volume Per Session</CardTitle>
              </CardHeader>
              <CardContent>
                <VolumePerSessionChart data={volumePerSession} unit={unit} />
              </CardContent>
            </Card>
          )}

          {/* Session History */}
          <div>
            <h2 className="mb-3 text-lg font-semibold">Session History</h2>
            {sessionHistory.length === 0 ? (
              <Card>
                <CardContent className="pt-6 text-center text-muted-foreground">
                  No session history yet
                </CardContent>
              </Card>
            ) : (
              <div className="grid gap-3">
                {sessionHistory.map((session) => (
                  <Card key={session.sessionId}>
                    <CardContent className="pt-6">
                      <div className="flex items-center justify-between mb-3">
                        <span className="text-sm font-medium text-muted-foreground">
                          {new Date(session.date).toLocaleDateString("en-US", {
                            weekday: "short",
                            month: "short",
                            day: "numeric",
                            year: "numeric",
                          })}
                        </span>
                        <span className="text-sm font-semibold">
                          {session.sets.length} {session.sets.length === 1 ? "set" : "sets"}
                        </span>
                      </div>
                      <div className="flex flex-wrap gap-2">
                        {session.sets.map((set, index) => (
                          <div
                            key={index}
                            className="px-3 py-1.5 bg-zinc-100 dark:bg-zinc-800 rounded-md text-sm font-medium"
                          >
                            {set.reps} × {formatWeight(set.weight, unit)}
                          </div>
                        ))}
                      </div>
                    </CardContent>
                  </Card>
                ))}
              </div>
            )}
          </div>
        </div>
      </main>
    </div>
  );
}
