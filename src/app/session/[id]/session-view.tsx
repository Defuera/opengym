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
import ExerciseStrip from "./exercise-strip";
import AddExerciseDialog from "./add-exercise-dialog";
import ExerciseSetList from "./components/exercise-set-list";
import ExerciseSetEditor from "./components/exercise-set-editor";

type Set = {
  id: string;
  reps: number;
  weight: number;
  order: number;
  status: "todo" | "later" | "complete";
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
  const [isSaving, setIsSaving] = useState(false);
  const [isDrawerOpen, setIsDrawerOpen] = useState(false);
  const [isAddExerciseOpen, setIsAddExerciseOpen] = useState(false);
  const [isEditorOpen, setIsEditorOpen] = useState(false);
  const [editingSet, setEditingSet] = useState<Set | null>(null);
  const [isNewSet, setIsNewSet] = useState(false);

  const currentExercise = session.exercises[currentExerciseIndex];

  const handleSetClick = (setId: string) => {
    const set = currentExercise.sets.find((s) => s.id === setId);
    if (set) {
      setEditingSet(set);
      setIsNewSet(false);
      setIsEditorOpen(true);
    }
  };

  const handleAddSet = async () => {
    // Fetch last values for this exercise
    try {
      const response = await fetch(
        `/api/exercises/last-values?name=${encodeURIComponent(currentExercise.name)}`
      );
      const lastValues = await response.json();

      const defaultReps = lastValues?.reps ?? 12;
      const defaultWeight = lastValues?.weight ?? 0;

      setEditingSet({
        id: "",
        reps: defaultReps,
        weight: defaultWeight,
        order: currentExercise.sets.length,
        status: "todo",
      });
      setIsNewSet(true);
      setIsEditorOpen(true);
    } catch (error) {
      console.error("Failed to fetch last values:", error);
      // Use defaults if fetch fails
      setEditingSet({
        id: "",
        reps: 12,
        weight: 0,
        order: currentExercise.sets.length,
        status: "todo",
      });
      setIsNewSet(true);
      setIsEditorOpen(true);
    }
  };

  const handleSaveSet = async (data: {
    reps: number;
    weight: number;
    status: "todo" | "later" | "complete";
  }) => {
    try {
      if (isNewSet) {
        // Create new set
        await fetch(`/api/exercises/${currentExercise.id}/sets`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            reps: data.reps,
            weight: data.weight,
            order: currentExercise.sets.length,
          }),
        });

        // If status is not todo, update it
        if (data.status !== "todo") {
          router.refresh();
          // Wait for refresh then update status
          setTimeout(async () => {
            const updatedExercise = session.exercises[currentExerciseIndex];
            const newSet = updatedExercise.sets[updatedExercise.sets.length - 1];
            if (newSet) {
              await fetch(`/api/sets/${newSet.id}`, {
                method: "PATCH",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ status: data.status }),
              });
            }
            router.refresh();
          }, 100);
        } else {
          router.refresh();
        }
      } else if (editingSet) {
        // Update existing set
        await fetch(`/api/sets/${editingSet.id}`, {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(data),
        });
        router.refresh();
      }
    } catch (error) {
      console.error("Failed to save set:", error);
    }
  };

  const handleDeleteSet = async () => {
    if (editingSet && !isNewSet) {
      try {
        await fetch(`/api/sets/${editingSet.id}`, {
          method: "DELETE",
        });
        router.refresh();
      } catch (error) {
        console.error("Failed to delete set:", error);
      }
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
                <CardContent>
                  <ExerciseSetList
                    sets={currentExercise.sets}
                    onSetClick={handleSetClick}
                    onAddSet={handleAddSet}
                  />
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

      <ExerciseSetEditor
        open={isEditorOpen}
        onOpenChange={setIsEditorOpen}
        set={editingSet}
        isNewSet={isNewSet}
        onSave={handleSaveSet}
        onDelete={handleDeleteSet}
      />
    </div>
  );
}
