import Link from "next/link";
import { prisma } from "@/lib/prisma";
import StartSessionButton from "./start-session-button";

export default async function Home() {
  const sessions = await prisma.session.findMany({
    where: {
      userId: "default-user",
    },
    orderBy: {
      date: "desc",
    },
    take: 10,
    include: {
      exercises: {
        include: {
          sets: true,
        },
      },
    },
  });

  type SessionWithExercisesAndSets = (typeof sessions)[number];

  return (
    <div className="flex min-h-screen flex-col bg-zinc-50 dark:bg-black">
      <header className="border-b border-zinc-200 bg-white px-4 py-6 dark:border-zinc-800 dark:bg-zinc-900">
        <h1 className="text-2xl font-bold text-zinc-900 dark:text-zinc-50">
          OpenGym
        </h1>
      </header>

      <main className="flex-1 px-4 py-6">
        <div className="mx-auto max-w-2xl space-y-6">
          <StartSessionButton />

          <div>
            <h2 className="mb-4 text-lg font-semibold text-zinc-900 dark:text-zinc-50">
              Recent Sessions
            </h2>

            {sessions.length === 0 ? (
              <p className="text-zinc-600 dark:text-zinc-400">
                No sessions yet. Start your first workout!
              </p>
            ) : (
              <div className="space-y-3">
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
                      className="block rounded-lg border border-zinc-200 bg-white p-4 transition-colors hover:bg-zinc-50 dark:border-zinc-800 dark:bg-zinc-900 dark:hover:bg-zinc-800"
                    >
                      <div className="flex items-start justify-between">
                        <div className="flex-1">
                          <div className="mb-1 flex items-center gap-2">
                            <p className="font-medium text-zinc-900 dark:text-zinc-50">
                              {new Date(session.date).toLocaleDateString(
                                "en-US",
                                {
                                  weekday: "short",
                                  month: "short",
                                  day: "numeric",
                                }
                              )}
                            </p>
                            {session.status === "active" && (
                              <span className="rounded-full bg-green-100 px-2 py-0.5 text-xs font-medium text-green-700 dark:bg-green-900 dark:text-green-300">
                                Active
                              </span>
                            )}
                          </div>
                          <p className="text-sm text-zinc-600 dark:text-zinc-400">
                            {session.exercises.length}{" "}
                            {session.exercises.length === 1
                              ? "exercise"
                              : "exercises"}{" "}
                            · {totalSets}{" "}
                            {totalSets === 1 ? "set" : "sets"}
                            {totalVolume > 0 &&
                              ` · ${Math.round(totalVolume)} lbs`}
                          </p>
                        </div>
                      </div>
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
