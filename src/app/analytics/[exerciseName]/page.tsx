import { workoutRepository } from "@/lib/repositories";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { formatWeight } from "@/lib/units";
import { ExerciseProgressChart } from "./exercise-charts";
import { SessionHistory } from "./session-history";
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
      <main className="flex-1 px-4 pb-24">
        <div className="mx-auto max-w-2xl space-y-6 pt-6">
          <h1 className="text-3xl font-bold">{decodedName}</h1>

          {/* Personal Records */}
          <div>
            <h2 className="mb-3 text-lg font-semibold">Personal Records</h2>
            <div className="grid grid-cols-3 gap-2">
              <Card className="bg-white dark:bg-zinc-900 border-2">
                <CardContent className="p-3">
                  <p className="text-[10px] text-muted-foreground mb-1">Max Weight</p>
                  <p className="text-lg font-bold">
                    {formatWeight(personalRecords.maxWeight, unit)}
                  </p>
                </CardContent>
              </Card>

              <Card className="bg-white dark:bg-zinc-900 border-2">
                <CardContent className="p-3">
                  <p className="text-[10px] text-muted-foreground mb-1">Best Set</p>
                  <p className="text-lg font-bold">
                    {personalRecords.maxRepsAtHeaviestWeight.reps} × {formatWeight(personalRecords.maxRepsAtHeaviestWeight.weight, unit)}
                  </p>
                </CardContent>
              </Card>

              <Card className="bg-white dark:bg-zinc-900 border-2">
                <CardContent className="p-3">
                  <p className="text-[10px] text-muted-foreground mb-1">Sessions</p>
                  <p className="text-lg font-bold">
                    {sessionHistory.length}
                  </p>
                </CardContent>
              </Card>
            </div>
          </div>

          {/* Progress Chart */}
          {weightProgression.length > 0 && (
            <Card>
              <CardHeader>
                <CardTitle className="text-base">Progress</CardTitle>
              </CardHeader>
              <CardContent>
                <ExerciseProgressChart
                  weightData={weightProgression}
                  volumeData={volumePerSession}
                  unit={unit}
                />
              </CardContent>
            </Card>
          )}

          {/* Session History */}
          <div>
            <h2 className="mb-3 text-lg font-semibold">Session History</h2>
            <SessionHistory sessionHistory={sessionHistory} unit={unit} />
          </div>
        </div>
      </main>
    </div>
  );
}
