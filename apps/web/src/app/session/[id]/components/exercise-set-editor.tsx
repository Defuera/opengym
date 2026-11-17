"use client";

import { useState, useEffect } from "react";
import {
  Drawer,
  DrawerContent,
  DrawerHeader,
  DrawerTitle,
} from "@/components/ui/drawer";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Minus, Plus, Trash2 } from "lucide-react";
import { convertWeightForDisplay, getUnitLabel, getWeightIncrement, type Unit } from "@/lib/units";

type Set = {
  id: string;
  reps: number;
  weight: number;
  order: number;
  status: "todo" | "later" | "complete";
};

type ExerciseSetEditorProps = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  set: Set | null;
  isNewSet?: boolean;
  onSave: (data: {
    reps: number;
    weight: number;
    status: "todo" | "later" | "complete";
  }) => void;
  onDelete?: () => void;
  unit: Unit;
};

export default function ExerciseSetEditor({
  open,
  onOpenChange,
  set,
  isNewSet = false,
  onSave,
  onDelete,
  unit,
}: ExerciseSetEditorProps) {
  const [reps, setReps] = useState(set?.reps ?? 12);
  const [weight, setWeight] = useState(
    set ? convertWeightForDisplay(set.weight, unit) : 0
  );

  useEffect(() => {
    if (set) {
      setReps(set.reps);
      setWeight(convertWeightForDisplay(set.weight, unit));
    }
  }, [set, unit]);

  const handleComplete = () => {
    onSave({ reps, weight, status: "complete" });
    onOpenChange(false);
  };

  const handleMarkLater = () => {
    onSave({ reps, weight, status: "later" });
    onOpenChange(false);
  };

  const handleDelete = () => {
    if (onDelete) {
      onDelete();
      onOpenChange(false);
    }
  };

  const adjustReps = (delta: number) => {
    setReps(Math.max(0, reps + delta));
  };

  const adjustWeight = (delta: number) => {
    const increment = getWeightIncrement(unit);
    setWeight(Math.max(0, weight + delta * increment));
  };

  return (
    <Drawer open={open} onOpenChange={onOpenChange}>
      <DrawerContent>
        <DrawerHeader>
          <DrawerTitle>{isNewSet ? "New Set" : "Edit Set"}</DrawerTitle>
        </DrawerHeader>
        <div className="p-4 space-y-6">
          <div className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="reps">Reps</Label>
              <div className="flex items-center gap-2">
                <Button
                  type="button"
                  variant="outline"
                  size="icon"
                  onClick={() => adjustReps(-1)}
                  className="h-12 w-12 shrink-0"
                >
                  <Minus className="h-4 w-4" />
                </Button>
                <Input
                  id="reps"
                  type="number"
                  value={reps}
                  onChange={(e: React.ChangeEvent<HTMLInputElement>) => setReps(Math.max(0, parseInt(e.target.value) || 0))}
                  className="text-center text-lg font-semibold h-12"
                  min="0"
                />
                <Button
                  type="button"
                  variant="outline"
                  size="icon"
                  onClick={() => adjustReps(1)}
                  className="h-12 w-12 shrink-0"
                >
                  <Plus className="h-4 w-4" />
                </Button>
              </div>
            </div>

            <div className="space-y-2">
              <Label htmlFor="weight">Weight ({getUnitLabel(unit)})</Label>
              <div className="flex items-center gap-2">
                <Button
                  type="button"
                  variant="outline"
                  size="icon"
                  onClick={() => adjustWeight(-1)}
                  className="h-12 w-12 shrink-0"
                >
                  <Minus className="h-4 w-4" />
                </Button>
                <Input
                  id="weight"
                  type="number"
                  value={weight}
                  onChange={(e: React.ChangeEvent<HTMLInputElement>) => setWeight(Math.max(0, parseFloat(e.target.value) || 0))}
                  className="text-center text-lg font-semibold h-12"
                  step={getWeightIncrement(unit)}
                  min="0"
                />
                <Button
                  type="button"
                  variant="outline"
                  size="icon"
                  onClick={() => adjustWeight(1)}
                  className="h-12 w-12 shrink-0"
                >
                  <Plus className="h-4 w-4" />
                </Button>
              </div>
            </div>
          </div>

          <div className="space-y-2">
            <Button
              onClick={handleComplete}
              className="w-full h-12 bg-green-600 hover:bg-green-700"
            >
              Complete
            </Button>
            <Button
              onClick={handleMarkLater}
              variant="outline"
              className="w-full h-12 border-amber-500 text-amber-600 hover:bg-amber-50 dark:hover:bg-amber-950/20"
            >
              Mark Later
            </Button>
            {!isNewSet && onDelete && (
              <Button
                onClick={handleDelete}
                variant="outline"
                className="w-full h-12 border-red-500 text-red-600 hover:bg-red-50 dark:hover:bg-red-950/20"
              >
                <Trash2 className="h-4 w-4 mr-2" />
                Delete
              </Button>
            )}
          </div>
        </div>
      </DrawerContent>
    </Drawer>
  );
}
