"use client";

import { useState } from "react";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";

type AddExerciseDialogProps = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onAdd: (data: {
    name: string;
    muscleGroup: string;
    numSets: number;
    defaultReps: number;
    defaultWeight: number;
  }) => void;
};

export default function AddExerciseDialog({
  open,
  onOpenChange,
  onAdd,
}: AddExerciseDialogProps) {
  const [name, setName] = useState("");
  const [muscleGroup, setMuscleGroup] = useState("");
  const [numSets, setNumSets] = useState(3);
  const [defaultReps, setDefaultReps] = useState(10);
  const [defaultWeight, setDefaultWeight] = useState(0);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) return;

    onAdd({
      name: name.trim(),
      muscleGroup: muscleGroup.trim() || "general",
      numSets,
      defaultReps,
      defaultWeight,
    });

    setName("");
    setMuscleGroup("");
    setNumSets(3);
    setDefaultReps(10);
    setDefaultWeight(0);
    onOpenChange(false);
  };

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="h-[90vh]">
        <SheetHeader>
          <SheetTitle>Add Exercise</SheetTitle>
          <SheetDescription>
            Add a new exercise to your current session
          </SheetDescription>
        </SheetHeader>
        <form onSubmit={handleSubmit} className="space-y-4 mt-6">
          <div className="space-y-2">
            <label
              htmlFor="name"
              className="text-sm font-medium text-foreground"
            >
              Exercise Name
            </label>
            <input
              id="name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. Bench Press"
              required
              autoFocus
              className="flex h-12 w-full rounded-lg border-2 border-border bg-background px-3 py-2 text-base focus:border-primary focus:outline-none"
            />
          </div>
          <div className="space-y-2">
            <label
              htmlFor="muscleGroup"
              className="text-sm font-medium text-foreground"
            >
              Muscle Group
            </label>
            <input
              id="muscleGroup"
              value={muscleGroup}
              onChange={(e) => setMuscleGroup(e.target.value)}
              placeholder="e.g. chest (optional)"
              className="flex h-12 w-full rounded-lg border-2 border-border bg-background px-3 py-2 text-base focus:border-primary focus:outline-none"
            />
          </div>
          <div className="space-y-2">
            <label
              htmlFor="numSets"
              className="text-sm font-medium text-foreground"
            >
              Number of Sets
            </label>
            <input
              id="numSets"
              type="number"
              inputMode="numeric"
              min="1"
              max="10"
              value={numSets}
              onChange={(e) => setNumSets(parseInt(e.target.value) || 1)}
              className="flex h-12 w-full rounded-lg border-2 border-border bg-background px-3 py-2 text-base text-center focus:border-primary focus:outline-none"
            />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <label
                htmlFor="defaultReps"
                className="text-sm font-medium text-foreground"
              >
                Default Reps
              </label>
              <input
                id="defaultReps"
                type="number"
                inputMode="numeric"
                min="0"
                value={defaultReps}
                onChange={(e) =>
                  setDefaultReps(parseInt(e.target.value) || 0)
                }
                className="flex h-12 w-full rounded-lg border-2 border-border bg-background px-3 py-2 text-base text-center focus:border-primary focus:outline-none"
              />
            </div>
            <div className="space-y-2">
              <label
                htmlFor="defaultWeight"
                className="text-sm font-medium text-foreground"
              >
                Default Weight
              </label>
              <input
                id="defaultWeight"
                type="number"
                inputMode="decimal"
                step="0.5"
                min="0"
                value={defaultWeight}
                onChange={(e) =>
                  setDefaultWeight(parseFloat(e.target.value) || 0)
                }
                className="flex h-12 w-full rounded-lg border-2 border-border bg-background px-3 py-2 text-base text-center focus:border-primary focus:outline-none"
              />
            </div>
          </div>
          <div className="flex gap-2 pt-4">
            <Button
              type="button"
              variant="outline"
              onClick={() => onOpenChange(false)}
              className="flex-1 h-12"
            >
              Cancel
            </Button>
            <Button type="submit" className="flex-1 h-12">
              Add Exercise
            </Button>
          </div>
        </form>
      </SheetContent>
    </Sheet>
  );
}
