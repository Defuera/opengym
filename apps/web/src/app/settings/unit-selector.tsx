"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { useRouter } from "next/navigation";

export default function UnitSelector({
  currentUnit,
}: {
  currentUnit: "metric" | "imperial";
}) {
  const [selectedUnit, setSelectedUnit] = useState(currentUnit);
  const [isLoading, setIsLoading] = useState(false);
  const router = useRouter();

  const handleUnitChange = async (unit: "metric" | "imperial") => {
    setSelectedUnit(unit);
    setIsLoading(true);

    try {
      const response = await fetch("/api/settings/unit", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ unit }),
      });

      if (!response.ok) {
        throw new Error("Failed to update unit preference");
      }

      router.refresh();
    } catch (error) {
      console.error("Error updating unit:", error);
      setSelectedUnit(currentUnit);
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="space-y-3">
      <p className="text-sm text-zinc-600 dark:text-zinc-400">
        Choose how weights are displayed throughout the app
      </p>
      <div className="flex gap-3">
        <Button
          variant={selectedUnit === "metric" ? "default" : "outline"}
          size="lg"
          onClick={() => handleUnitChange("metric")}
          disabled={isLoading}
          className="flex-1"
        >
          Metric (kg)
        </Button>
        <Button
          variant={selectedUnit === "imperial" ? "default" : "outline"}
          size="lg"
          onClick={() => handleUnitChange("imperial")}
          disabled={isLoading}
          className="flex-1"
        >
          Imperial (lbs)
        </Button>
      </div>
    </div>
  );
}
