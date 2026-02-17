"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Drawer,
  DrawerContent,
  DrawerHeader,
  DrawerTitle,
  DrawerTrigger,
} from "@/components/ui/drawer";

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
  const [isDrawerOpen, setIsDrawerOpen] = useState(false);

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

  const handleExerciseSelect = (index: number) => {
    setCurrentExerciseIndex(index);
    setIsDrawerOpen(false);
  };

  return (
    <div className="flex min-h-screen flex-col bg-zinc-50 dark:bg-zinc-950">
      <header className="sticky top-0 z-10 border-b bg-white/80 backdrop-blur-lg px-4 py-4 dark:bg-zinc-900/80">
        <div className="flex items-center justify-between">
          <Link href="/">
            <Button variant="ghost" size="sm">
              ← Back
            </Button>
          </Link>
          <Badge variant="default" className="bg-green-600">
            Active Session
          </Badge>
          <Button
            onClick={handleCompleteSession}
            disabled={isSaving}
            variant="ghost"
            size="sm"
          >
            {isSaving ? "Saving..." : "Finish"}
          </Button>
        </div>
      </header>

      <main className="flex-1 px-4 py-6 pb-32">
        <div className="mx-auto max-w-2xl">
          {currentExercise && (
            <div className="space-y-6">
              <Card className="border-2 shadow-xl">
                <CardHeader className="pb-4">
                  <div className="flex items-start justify-between">
                    <div className="flex-1">
                      <CardTitle className="text-2xl mb-2">
                        {currentExercise.name}
                      </CardTitle>
                      <Badge variant="secondary" className="capitalize">
                        {currentExercise.muscleGroup}
                      </Badge>
                    </div>
                    <div className="text-sm text-muted-foreground">
                      {currentExerciseIndex + 1} / {session.exercises.length}
                    </div>
                  </div>
                </CardHeader>
                <CardContent className="space-y-4">
                  <div className="grid grid-cols-[50px_1fr_1fr] gap-3 text-sm font-semibold text-muted-foreground">
                    <div>Set</div>
                    <div className="text-center">Reps</div>
                    <div className="text-center">Weight</div>
                  </div>

                  {currentExercise.sets.map((set, index) => {
                    const currentSet = sets[set.id];
                    return (
                      <div
                        key={set.id}
                        className="grid grid-cols-[50px_1fr_1fr] gap-3 items-center"
                      >
                        <div className="flex items-center justify-center h-12 text-lg font-bold text-foreground">
                          {index + 1}
                        </div>
                        <input
                          type="number"
                          inputMode="numeric"
                          value={currentSet.reps || ""}
                          onChange={(e) =>
                            handleSetChange(
                              set.id,
                              "reps",
                              parseInt(e.target.value) || 0
                            )
                          }
                          className="h-12 rounded-lg border-2 bg-background px-4 text-center text-lg font-semibold focus:border-primary focus:outline-none"
                          placeholder="0"
                        />
                        <input
                          type="number"
                          inputMode="decimal"
                          value={currentSet.weight || ""}
                          onChange={(e) =>
                            handleSetChange(
                              set.id,
                              "weight",
                              parseFloat(e.target.value) || 0
                            )
                          }
                          className="h-12 rounded-lg border-2 bg-background px-4 text-center text-lg font-semibold focus:border-primary focus:outline-none"
                          placeholder="0"
                        />
                      </div>
                    );
                  })}
                </CardContent>
              </Card>
            </div>
          )}
        </div>
      </main>

      <div className="fixed bottom-0 left-0 right-0 border-t bg-white/95 backdrop-blur-lg p-4 dark:bg-zinc-900/95">
        <div className="mx-auto max-w-2xl space-y-3">
          <div className="flex gap-3">
            <Button
              onClick={() => setCurrentExerciseIndex(currentExerciseIndex - 1)}
              disabled={currentExerciseIndex === 0}
              variant="outline"
              size="lg"
              className="flex-1 h-12"
            >
              Previous
            </Button>
            <Drawer open={isDrawerOpen} onOpenChange={setIsDrawerOpen}>
              <DrawerTrigger asChild>
                <Button variant="outline" size="lg" className="h-12">
                  All ({session.exercises.length})
                </Button>
              </DrawerTrigger>
              <DrawerContent>
                <DrawerHeader>
                  <DrawerTitle>All Exercises</DrawerTitle>
                </DrawerHeader>
                <div className="p-4 space-y-2 max-h-[60vh] overflow-y-auto">
                  {session.exercises.map((exercise, index) => (
                    <button
                      key={exercise.id}
                      onClick={() => handleExerciseSelect(index)}
                      className={`w-full text-left p-4 rounded-lg border-2 transition-all ${
                        index === currentExerciseIndex
                          ? "border-primary bg-primary/5"
                          : "border-border hover:border-primary/50"
                      }`}
                    >
                      <div className="flex items-center justify-between">
                        <div>
                          <p className="font-semibold">{exercise.name}</p>
                          <p className="text-sm text-muted-foreground capitalize">
                            {exercise.muscleGroup} · {exercise.sets.length} sets
                          </p>
                        </div>
                        {index === currentExerciseIndex && (
                          <Badge variant="default">Current</Badge>
                        )}
                      </div>
                    </button>
                  ))}
                </div>
              </DrawerContent>
            </Drawer>
            <Button
              onClick={() => setCurrentExerciseIndex(currentExerciseIndex + 1)}
              disabled={currentExerciseIndex >= session.exercises.length - 1}
              variant="default"
              size="lg"
              className="flex-1 h-12"
            >
              Next
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
