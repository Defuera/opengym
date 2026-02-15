"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";

type Set = {
  id: string;
  reps: number;
  weight: number;
  order: number;
};

type Exercise = {
  id: string;
  name: string;
  muscleGroup: string;
  order: number;
  sets: Set[];
};

type Session = {
  id: string;
  date: Date;
  status: string;
  exercises: Exercise[];
};

export default function SessionView({ session }: { session: Session }) {
  const router = useRouter();
  const [currentExerciseIndex, setCurrentExerciseIndex] = useState(0);
  const [sets, setSets] = useState<{ [key: string]: Set }>(
    session.exercises.reduce(
      (acc, ex) => {
        ex.sets.forEach((set) => {
          acc[set.id] = set;
        });
        return acc;
      },
      {} as { [key: string]: Set }
    )
  );
  const [isSaving, setIsSaving] = useState(false);

  const currentExercise = session.exercises[currentExerciseIndex];

  const handleSetChange = async (
    setId: string,
    field: "reps" | "weight",
    value: number
  ) => {
    setSets((prev) => ({
      ...prev,
      [setId]: {
        ...prev[setId],
        [field]: value,
      },
    }));

    try {
      await fetch(`/api/sets/${setId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ [field]: value }),
      });
    } catch (error) {
      console.error("Failed to update set:", error);
    }
  };

  const handleCompleteSession = async () => {
    setIsSaving(true);
    try {
      await fetch(`/api/sessions/${session.id}/complete`, {
        method: "POST",
      });
      router.push(`/session/${session.id}/summary`);
    } catch (error) {
      console.error("Failed to complete session:", error);
      setIsSaving(false);
    }
  };

  return (
    <div className="flex min-h-screen flex-col bg-zinc-50 dark:bg-black">
      <header className="border-b border-zinc-200 bg-white px-4 py-4 dark:border-zinc-800 dark:bg-zinc-900">
        <div className="flex items-center justify-between">
          <Link
            href="/"
            className="text-sm font-medium text-blue-600 dark:text-blue-400"
          >
            ← Back
          </Link>
          <h1 className="text-lg font-semibold text-zinc-900 dark:text-zinc-50">
            Active Session
          </h1>
          <button
            onClick={handleCompleteSession}
            disabled={isSaving}
            className="text-sm font-medium text-blue-600 disabled:opacity-50 dark:text-blue-400"
          >
            {isSaving ? "Saving..." : "Finish"}
          </button>
        </div>
      </header>

      <main className="flex-1 px-4 py-6">
        <div className="mx-auto max-w-2xl space-y-6">
          {/* Exercise navigation */}
          <div className="flex gap-2 overflow-x-auto pb-2">
            {session.exercises.map((exercise, index) => (
              <button
                key={exercise.id}
                onClick={() => setCurrentExerciseIndex(index)}
                className={`flex-shrink-0 rounded-lg border px-4 py-2 text-sm font-medium transition-colors ${
                  index === currentExerciseIndex
                    ? "border-blue-600 bg-blue-50 text-blue-700 dark:border-blue-500 dark:bg-blue-950 dark:text-blue-300"
                    : "border-zinc-200 bg-white text-zinc-700 hover:bg-zinc-50 dark:border-zinc-800 dark:bg-zinc-900 dark:text-zinc-300 dark:hover:bg-zinc-800"
                }`}
              >
                {exercise.name}
              </button>
            ))}
          </div>

          {/* Main exercise card */}
          {currentExercise && (
            <div className="rounded-lg border border-zinc-200 bg-white p-6 dark:border-zinc-800 dark:bg-zinc-900">
              <h2 className="mb-2 text-2xl font-bold text-zinc-900 dark:text-zinc-50">
                {currentExercise.name}
              </h2>
              <p className="mb-6 text-sm text-zinc-600 dark:text-zinc-400">
                {currentExercise.muscleGroup}
              </p>

              <div className="space-y-4">
                <div className="grid grid-cols-[40px_1fr_1fr] gap-4 text-sm font-medium text-zinc-600 dark:text-zinc-400">
                  <div>Set</div>
                  <div>Reps</div>
                  <div>Weight (lbs)</div>
                </div>

                {currentExercise.sets.map((set, index) => {
                  const currentSet = sets[set.id];
                  return (
                    <div
                      key={set.id}
                      className="grid grid-cols-[40px_1fr_1fr] gap-4"
                    >
                      <div className="flex items-center text-sm font-medium text-zinc-900 dark:text-zinc-50">
                        {index + 1}
                      </div>
                      <input
                        type="number"
                        value={currentSet.reps || ""}
                        onChange={(e) =>
                          handleSetChange(
                            set.id,
                            "reps",
                            parseInt(e.target.value) || 0
                          )
                        }
                        className="rounded-lg border border-zinc-200 bg-white px-3 py-2 text-center text-base font-medium text-zinc-900 focus:border-blue-500 focus:outline-none dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-50"
                        placeholder="0"
                      />
                      <input
                        type="number"
                        value={currentSet.weight || ""}
                        onChange={(e) =>
                          handleSetChange(
                            set.id,
                            "weight",
                            parseFloat(e.target.value) || 0
                          )
                        }
                        className="rounded-lg border border-zinc-200 bg-white px-3 py-2 text-center text-base font-medium text-zinc-900 focus:border-blue-500 focus:outline-none dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-50"
                        placeholder="0"
                      />
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          {/* Navigation buttons */}
          <div className="flex gap-3">
            {currentExerciseIndex > 0 && (
              <button
                onClick={() => setCurrentExerciseIndex(currentExerciseIndex - 1)}
                className="flex-1 rounded-lg border border-zinc-200 bg-white py-3 font-medium text-zinc-900 transition-colors hover:bg-zinc-50 dark:border-zinc-800 dark:bg-zinc-900 dark:text-zinc-50 dark:hover:bg-zinc-800"
              >
                Previous
              </button>
            )}
            {currentExerciseIndex < session.exercises.length - 1 && (
              <button
                onClick={() => setCurrentExerciseIndex(currentExerciseIndex + 1)}
                className="flex-1 rounded-lg bg-blue-600 py-3 font-medium text-white transition-colors hover:bg-blue-700 active:bg-blue-800"
              >
                Next Exercise
              </button>
            )}
          </div>
        </div>
      </main>
    </div>
  );
}
