import { workoutRepository } from "@/lib/repositories";
import { notFound } from "next/navigation";
import Link from "next/link";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { formatWeight, convertWeightForDisplay, getUnitLabel } from "@/lib/units";
import ReviewSection from "./ReviewSection";
export const dynamic = 'force-dynamic';

export default async function SessionSummaryPage({
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

  const totalSets = session.exercises.reduce(
    (acc, ex) => acc + ex.sets.length,
    0
  );

  const totalVolume = session.exercises.reduce(
    (acc, ex) =>
      acc +
      ex.sets.reduce((setAcc, set) => setAcc + set.reps * set.weight, 0),
    0
  );

  const totalReps = session.exercises.reduce(
    (acc, ex) => acc + ex.sets.reduce((setAcc, set) => setAcc + set.reps, 0),
    0
  );

  const muscleGroups = Array.from(
    new Set(session.exercises.map((ex) => ex.muscleGroup))
  );

  return (
    <div className="flex min-h-screen flex-col bg-zinc-50 dark:bg-zinc-950">
      <main className="flex-1 px-4 py-6 pb-24">
        <div className="mx-auto max-w-2xl space-y-6">
          <div>
            <h1 className="text-2xl font-bold text-zinc-900 dark:text-zinc-50">
              Session Complete
            </h1>
            <p className="mt-1 text-sm text-muted-foreground">
              {new Date(session.date).toLocaleDateString("en-US", {
                weekday: "long",
                month: "long",
                day: "numeric",
                year: "numeric",
              })}
            </p>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Card>
              <CardContent className="pt-6">
                <p className="text-sm text-muted-foreground mb-1">
                  Total Volume
                </p>
                <p className="text-3xl font-bold">
                  {Math.round(convertWeightForDisplay(totalVolume, unit))}
                  <span className="text-lg text-muted-foreground ml-1">{getUnitLabel(unit)}</span>
                </p>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="pt-6">
                <p className="text-sm text-muted-foreground mb-1">
                  Total Reps
                </p>
                <p className="text-3xl font-bold">
                  {totalReps}
                </p>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="pt-6">
                <p className="text-sm text-muted-foreground mb-1">
                  Exercises
                </p>
                <p className="text-3xl font-bold">
                  {session.exercises.length}
                </p>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="pt-6">
                <p className="text-sm text-muted-foreground mb-1">
                  Total Sets
                </p>
                <p className="text-3xl font-bold">
                  {totalSets}
                </p>
              </CardContent>
            </Card>
          </div>

          <Card>
            <CardHeader>
              <CardTitle className="text-base">Muscle Groups Trained</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="flex flex-wrap gap-2">
                {muscleGroups.map((group) => (
                  <Badge key={group} variant="secondary" className="capitalize">
                    {group}
                  </Badge>
                ))}
              </div>
            </CardContent>
          </Card>

          <div>
            <h2 className="mb-3 text-lg font-semibold">
              Exercise Breakdown
            </h2>
            <div className="space-y-3">
              {session.exercises.map((exercise) => {
                const exerciseVolume = exercise.sets.reduce(
                  (acc, set) => acc + set.reps * set.weight,
                  0
                );
                const exerciseReps = exercise.sets.reduce(
                  (acc, set) => acc + set.reps,
                  0
                );

                return (
                  <Card key={exercise.id}>
                    <CardHeader className="pb-3">
                      <CardTitle className="text-base">
                        {exercise.name}
                      </CardTitle>
                      <p className="text-sm text-muted-foreground">
                        {exercise.sets.length} sets · {exerciseReps} reps ·{" "}
                        {formatWeight(exerciseVolume, unit)}
                      </p>
                    </CardHeader>
                    <CardContent className="pt-0">
                      <div className="space-y-2">
                        {exercise.sets.map((set, index) => (
                          <div
                            key={set.id}
                            className="flex items-center justify-between text-sm p-2 rounded bg-muted/50"
                          >
                            <span className="font-medium">Set {index + 1}</span>
                            <span className="text-muted-foreground">
                              {set.reps} reps × {formatWeight(set.weight, unit)}
                            </span>
                          </div>
                        ))}
                      </div>
                    </CardContent>
                  </Card>
                );
              })}
            </div>
          </div>

          <ReviewSection sessionId={id} userId={session.userId} isCompleted={session.status === "completed"} />
        </div>
      </main>

      <div className="fixed bottom-0 left-0 right-0 border-t bg-white/95 backdrop-blur-lg p-4 dark:bg-zinc-900/95">
        <div className="mx-auto max-w-2xl">
          <Link href="/">
            <Button size="lg" className="w-full h-14 text-base">
              Back to Home
            </Button>
          </Link>
        </div>
      </div>
    </div>
  );
}
