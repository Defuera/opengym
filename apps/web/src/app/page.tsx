"use client";

import { useState } from "react";
import { useQuery } from "convex/react";
import { api } from "../../convex/_generated/api";
import { Card, CardContent } from "@/components/ui/card";
import { formatWeight } from "@/lib/units";
import Link from "next/link";
import { WeeklyCarousel } from "@/components/weekly-carousel";

export default function Home() {
  const [currentTime] = useState(() => Date.now());
  const user = useQuery(api.users.getDefaultUser, {});
  const exerciseAnalytics = useQuery(
    api.analytics.getExerciseAnalytics,
    user ? { userId: user._id } : "skip"
  );
  const weeklyData = useQuery(
    api.sessions.getWeeklySessionsWithSummaries,
    user ? { userId: user._id, weeksBack: 8 } : "skip"
  );

  const unit = user?.unit ?? "metric";

  if (!exerciseAnalytics || !weeklyData) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-zinc-50 dark:bg-zinc-950">
        <div className="text-lg text-muted-foreground">Loading...</div>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen flex-col bg-zinc-50 dark:bg-zinc-950">
      <main className="flex-1 pb-24">
        {/* Weekly Carousel — full bleed, no horizontal padding */}
        <div className="mx-auto max-w-2xl pt-6 px-4">
          <h2 className="mb-3 text-lg font-semibold">Weekly Overview</h2>
        </div>
        <WeeklyCarousel weeks={weeklyData} />

        <div className="mx-auto max-w-2xl space-y-6 px-4 mt-6">
          {/* Exercise Cards */}
          <div>
            <h2 className="mb-3 text-lg font-semibold">Exercises</h2>
            {exerciseAnalytics.length === 0 ? (
              <Card>
                <CardContent className="pt-6 text-center text-muted-foreground">
                  No exercise data yet
                </CardContent>
              </Card>
            ) : (
              <div className="grid gap-3">
                {exerciseAnalytics.map((exercise) => (
                  <Link
                    key={exercise.name}
                    href={`/analytics/${encodeURIComponent(exercise.name)}`}
                  >
                    <Card className="transition-all active:scale-[0.98] hover:shadow-md">
                      <CardContent className="pt-6">
                        <div className="flex items-center justify-between">
                          <div className="flex-1">
                            <h3 className="font-semibold">{exercise.name}</h3>
                            <p className="text-sm text-muted-foreground capitalize">
                              {exercise.muscleGroup}
                            </p>
                          </div>
                          <div className="flex items-center gap-3">
                            <div className="text-right">
                              <p className="font-semibold">
                                {formatWeight(exercise.lastWeight, unit)}
                              </p>
                              <p className="text-xs text-muted-foreground">
                                {exercise.sessionCount}{" "}
                                {exercise.sessionCount === 1 ? "session" : "sessions"}
                              </p>
                            </div>
                            <div className="text-2xl">
                              {exercise.trend === "up" && "↑"}
                              {exercise.trend === "down" && "↓"}
                              {exercise.trend === "stable" && "→"}
                            </div>
                          </div>
                        </div>
                      </CardContent>
                    </Card>
                  </Link>
                ))}
              </div>
            )}
          </div>
        </div>
      </main>
    </div>
  );
}
