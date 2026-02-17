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
import { WheelPicker } from "@/components/ui/wheel-picker";
import ExerciseStrip from "./exercise-strip";
import AddExerciseDialog from "./add-exercise-dialog";

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
  const [isAddExerciseOpen, setIsAddExerciseOpen] = useState(false);

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

    // Debounce the API call slightly to avoid too many requests during dragging
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

  const handleAddExercise = async (data: {
    name: string;
    muscleGroup: string;
    numSets: number;
    defaultReps: number;
    defaultWeight: number;
  }) => {
    try {
      const sets = Array.from({ length: data.numSets }, (_, i) => ({
        reps: data.defaultReps,
        weight: data.defaultWeight,
        order: i,
      }));

      await fetch(`/api/sessions/${session.id}/exercises`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: data.name,
          muscleGroup: data.muscleGroup,
          sets,
        }),
      });

      router.refresh();
      setCurrentExerciseIndex(session.exercises.length);
    } catch (error) {
      console.error("Failed to add exercise:", error);
    }
  };

  return (
    <div className="flex min-h-screen w-full flex-col overflow-x-hidden bg-zinc-50 dark:bg-zinc-950">
      <header className="sticky top-0 z-10 w-full border-b bg-white/80 backdrop-blur-lg px-4 py-4 dark:bg-zinc-900/80">
        <div className="flex items-center justify-between gap-2">
          <Link href="/">
            <Button variant="ghost" size="sm">
              ← Back
            </Button>
          </Link>
          <Badge variant="default" className="bg-green-600 shrink-0">
            Active Session
          </Badge>
          <Button
            onClick={handleCompleteSession}
            disabled={isSaving}
            variant="ghost"
            size="sm"
            className="shrink-0"
          >
            {isSaving ? "Saving..." : "Finish"}
          </Button>
        </div>
      </header>

      <ExerciseStrip
        exercises={session.exercises}
        currentIndex={currentExerciseIndex}
        onExerciseSelect={handleExerciseSelect}
        onAddExercise={() => setIsAddExerciseOpen(true)}
      />

      <main className="flex-1 w-full px-4 py-6 pb-32 overflow-x-hidden">
        <div className="mx-auto w-full max-w-2xl">
          {currentExercise && (
            <div className="w-full space-y-6">
              <Card className="w-full border-2 shadow-xl">
                <CardHeader className="pb-4">
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex-1 min-w-0">
                      <CardTitle className="text-2xl mb-2 break-words">
                        {currentExercise.name}
                      </CardTitle>
                      <Badge variant="secondary" className="capitalize">
                        {currentExercise.muscleGroup}
                      </Badge>
                    </div>
                    <div className="text-sm text-muted-foreground shrink-0">
                      {currentExerciseIndex + 1} / {session.exercises.length}
                    </div>
                  </div>
                </CardHeader>
                <CardContent className="space-y-3">
                  {currentExercise.sets.map((set, index) => {
                    const currentSet = sets[set.id];
                    return (
                      <div key={set.id} className="space-y-1">
                        <div className="text-center text-sm font-semibold text-muted-foreground">
                          Set {index + 1}
                        </div>
                        <div className="grid grid-cols-2 gap-4">
                          <WheelPicker
                            label="Reps"
                            value={currentSet.reps || 0}
                            onChange={(value) =>
                              handleSetChange(set.id, "reps", value)
                            }
                            min={0}
                            max={50}
                            step={1}
                          />
                          <WheelPicker
                            label="Weight"
                            value={currentSet.weight || 0}
                            onChange={(value) =>
                              handleSetChange(set.id, "weight", value)
                            }
                            min={0}
                            max={500}
                            step={5}
                          />
                        </div>
                        {index < currentExercise.sets.length - 1 && (
                          <div className="border-t pt-1" />
                        )}
                      </div>
                    );
                  })}
                </CardContent>
              </Card>
            </div>
          )}
        </div>
      </main>

      <div className="fixed bottom-0 left-0 right-0 w-full border-t bg-white/95 backdrop-blur-lg p-4 dark:bg-zinc-900/95">
        <div className="mx-auto w-full max-w-2xl">
          <div className="flex gap-2 w-full">
            <Button
              onClick={() => setCurrentExerciseIndex(currentExerciseIndex - 1)}
              disabled={currentExerciseIndex === 0}
              variant="outline"
              size="lg"
              className="flex-1 h-12 min-w-0"
            >
              Previous
            </Button>
            <Drawer open={isDrawerOpen} onOpenChange={setIsDrawerOpen}>
              <DrawerTrigger asChild>
                <Button variant="outline" size="lg" className="h-12 shrink-0">
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
                      <div className="flex items-center justify-between gap-2">
                        <div className="min-w-0 flex-1">
                          <p className="font-semibold break-words">{exercise.name}</p>
                          <p className="text-sm text-muted-foreground capitalize">
                            {exercise.muscleGroup} · {exercise.sets.length} sets
                          </p>
                        </div>
                        {index === currentExerciseIndex && (
                          <Badge variant="default" className="shrink-0">Current</Badge>
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
              className="flex-1 h-12 min-w-0"
            >
              Next
            </Button>
          </div>
        </div>
      </div>

      <AddExerciseDialog
        open={isAddExerciseOpen}
        onOpenChange={setIsAddExerciseOpen}
        onAdd={handleAddExercise}
      />
    </div>
  );
}
