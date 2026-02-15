import { prisma } from "@/lib/prisma";
import { notFound } from "next/navigation";
import Link from "next/link";

export default async function SessionSummaryPage({
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
    <div className="flex min-h-screen flex-col bg-zinc-50 dark:bg-black">
      <header className="border-b border-zinc-200 bg-white px-4 py-6 dark:border-zinc-800 dark:bg-zinc-900">
        <h1 className="text-2xl font-bold text-zinc-900 dark:text-zinc-50">
          Session Summary
        </h1>
        <p className="mt-1 text-sm text-zinc-600 dark:text-zinc-400">
          {new Date(session.date).toLocaleDateString("en-US", {
            weekday: "long",
            month: "long",
            day: "numeric",
            year: "numeric",
          })}
        </p>
      </header>

      <main className="flex-1 px-4 py-6">
        <div className="mx-auto max-w-2xl space-y-6">
          {/* Stats cards */}
          <div className="grid grid-cols-2 gap-3">
            <div className="rounded-lg border border-zinc-200 bg-white p-4 dark:border-zinc-800 dark:bg-zinc-900">
              <p className="text-sm text-zinc-600 dark:text-zinc-400">
                Total Volume
              </p>
              <p className="mt-1 text-2xl font-bold text-zinc-900 dark:text-zinc-50">
                {Math.round(totalVolume)} lbs
              </p>
            </div>
            <div className="rounded-lg border border-zinc-200 bg-white p-4 dark:border-zinc-800 dark:bg-zinc-900">
              <p className="text-sm text-zinc-600 dark:text-zinc-400">
                Total Reps
              </p>
              <p className="mt-1 text-2xl font-bold text-zinc-900 dark:text-zinc-50">
                {totalReps}
              </p>
            </div>
            <div className="rounded-lg border border-zinc-200 bg-white p-4 dark:border-zinc-800 dark:bg-zinc-900">
              <p className="text-sm text-zinc-600 dark:text-zinc-400">
                Exercises
              </p>
              <p className="mt-1 text-2xl font-bold text-zinc-900 dark:text-zinc-50">
                {session.exercises.length}
              </p>
            </div>
            <div className="rounded-lg border border-zinc-200 bg-white p-4 dark:border-zinc-800 dark:bg-zinc-900">
              <p className="text-sm text-zinc-600 dark:text-zinc-400">
                Total Sets
              </p>
              <p className="mt-1 text-2xl font-bold text-zinc-900 dark:text-zinc-50">
                {totalSets}
              </p>
            </div>
          </div>

          {/* Muscle groups */}
          <div className="rounded-lg border border-zinc-200 bg-white p-4 dark:border-zinc-800 dark:bg-zinc-900">
            <h2 className="mb-2 text-sm font-semibold text-zinc-900 dark:text-zinc-50">
              Muscle Groups Trained
            </h2>
            <div className="flex flex-wrap gap-2">
              {muscleGroups.map((group) => (
                <span
                  key={group}
                  className="rounded-full bg-blue-100 px-3 py-1 text-sm font-medium capitalize text-blue-700 dark:bg-blue-950 dark:text-blue-300"
                >
                  {group}
                </span>
              ))}
            </div>
          </div>

          {/* Exercise breakdown */}
          <div>
            <h2 className="mb-3 text-lg font-semibold text-zinc-900 dark:text-zinc-50">
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
                  <div
                    key={exercise.id}
                    className="rounded-lg border border-zinc-200 bg-white p-4 dark:border-zinc-800 dark:bg-zinc-900"
                  >
                    <h3 className="mb-1 font-semibold text-zinc-900 dark:text-zinc-50">
                      {exercise.name}
                    </h3>
                    <p className="mb-3 text-sm text-zinc-600 dark:text-zinc-400">
                      {exercise.sets.length} sets · {exerciseReps} reps ·{" "}
                      {Math.round(exerciseVolume)} lbs
                    </p>
                    <div className="space-y-1">
                      {exercise.sets.map((set, index) => (
                        <div
                          key={set.id}
                          className="flex items-center text-sm text-zinc-700 dark:text-zinc-300"
                        >
                          <span className="w-16">Set {index + 1}:</span>
                          <span>
                            {set.reps} reps × {set.weight} lbs
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

          {/* Back to home button */}
          <Link
            href="/"
            className="flex h-12 w-full items-center justify-center rounded-lg bg-blue-600 font-semibold text-white transition-colors hover:bg-blue-700 active:bg-blue-800"
          >
            Back to Home
          </Link>
        </div>
      </main>
    </div>
  );
}
