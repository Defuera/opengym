"use client";

import { Button } from "@/components/ui/button";
import { Plus } from "lucide-react";
import { cn } from "@/lib/utils";

type Set = {
  id: string;
  reps: number;
  weight: number;
  order: number;
  status: "todo" | "later" | "complete";
};

type ExerciseSetListProps = {
  sets: Set[];
  onSetClick: (setId: string) => void;
  onAddSet: () => void;
};

export default function ExerciseSetList({
  sets,
  onSetClick,
  onAddSet,
}: ExerciseSetListProps) {
  return (
    <div className="space-y-2">
      {sets.map((set, index) => (
        <button
          key={set.id}
          onClick={() => onSetClick(set.id)}
          className={cn(
            "w-full flex items-center justify-between p-3 rounded-lg border-2 transition-all text-left",
            set.status === "complete" &&
              "border-green-500 bg-green-50 dark:bg-green-950/20",
            set.status === "later" &&
              "border-amber-500 bg-amber-50 dark:bg-amber-950/20",
            set.status === "todo" &&
              "border-zinc-200 bg-white dark:border-zinc-700 dark:bg-zinc-900"
          )}
        >
          <div className="flex items-center gap-3 flex-1">
            <div
              className={cn(
                "flex items-center justify-center w-8 h-8 rounded-full font-semibold text-sm",
                set.status === "complete" &&
                  "bg-green-500 text-white",
                set.status === "later" &&
                  "bg-amber-500 text-white",
                set.status === "todo" &&
                  "bg-zinc-200 text-zinc-700 dark:bg-zinc-700 dark:text-zinc-300"
              )}
            >
              {index + 1}
            </div>
            <div className="flex-1">
              <div className="font-semibold text-base">
                {set.reps} × {set.weight}kg
              </div>
              <div className="text-xs text-muted-foreground capitalize">
                {set.status === "complete" && "Complete"}
                {set.status === "later" && "Later"}
                {set.status === "todo" && "To do"}
              </div>
            </div>
          </div>
        </button>
      ))}
      <Button
        onClick={onAddSet}
        variant="outline"
        className="w-full h-12 border-2 border-dashed hover:border-primary hover:bg-primary/5"
      >
        <Plus className="h-4 w-4 mr-2" />
        Add Set
      </Button>
    </div>
  );
}
