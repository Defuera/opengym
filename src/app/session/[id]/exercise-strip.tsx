"use client";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Plus } from "lucide-react";

type Exercise = {
  id: string;
  name: string;
  muscleGroup: string;
  order: number;
};

type ExerciseStripProps = {
  exercises: Exercise[];
  currentIndex: number;
  onExerciseSelect: (index: number) => void;
  onAddExercise: () => void;
};

export default function ExerciseStrip({
  exercises,
  currentIndex,
  onExerciseSelect,
  onAddExercise,
}: ExerciseStripProps) {
  return (
    <div className="w-full border-b bg-white dark:bg-zinc-900 px-4 py-3">
      <div className="w-full overflow-x-auto">
        <div className="flex gap-2 pb-2">
          {exercises.map((exercise, index) => {
            const isCurrent = index === currentIndex;
            const isPast = index < currentIndex;

            return (
              <button
                key={exercise.id}
                onClick={() => onExerciseSelect(index)}
                className={`
                  flex-shrink-0 px-4 py-2 rounded-lg border-2 transition-all
                  ${
                    isCurrent
                      ? "border-primary bg-primary/10 shadow-md"
                      : isPast
                        ? "border-green-500 bg-green-50 dark:bg-green-950/20"
                        : "border-border bg-background hover:border-primary/50"
                  }
                `}
              >
                <div className="flex flex-col items-start gap-1 min-w-[120px]">
                  <p className="text-sm font-semibold truncate w-full text-left">
                    {exercise.name}
                  </p>
                  <div className="flex items-center gap-1">
                    <Badge
                      variant="secondary"
                      className="text-xs capitalize h-5"
                    >
                      {exercise.muscleGroup}
                    </Badge>
                    {isCurrent && (
                      <Badge variant="default" className="text-xs h-5">
                        Current
                      </Badge>
                    )}
                    {isPast && (
                      <Badge
                        variant="outline"
                        className="text-xs h-5 border-green-500 text-green-600 dark:text-green-400"
                      >
                        Done
                      </Badge>
                    )}
                  </div>
                </div>
              </button>
            );
          })}
          <Button
            onClick={onAddExercise}
            variant="outline"
            size="icon"
            className="flex-shrink-0 h-[72px] w-12 border-2 border-dashed hover:border-primary hover:bg-primary/5"
          >
            <Plus className="h-5 w-5" />
          </Button>
        </div>
      </div>
    </div>
  );
}
