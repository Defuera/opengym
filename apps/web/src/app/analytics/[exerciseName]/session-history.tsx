"use client";

import { useState } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { formatWeight } from "@/lib/units";

type SessionHistoryItem = {
  sessionId: string;
  date: number;
  sets: { reps: number; weight: number }[];
};

export function SessionHistory({
  sessionHistory,
  unit,
}: {
  sessionHistory: SessionHistoryItem[];
  unit: "metric" | "imperial";
}) {
  const [showAll, setShowAll] = useState(false);
  const displayedSessions = showAll ? sessionHistory : sessionHistory.slice(0, 5);
  const hasMore = sessionHistory.length > 5;

  if (sessionHistory.length === 0) {
    return (
      <Card>
        <CardContent className="pt-6 text-center text-muted-foreground">
          No session history yet
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-3">
      <div className="grid gap-3">
        {displayedSessions.map((session) => (
          <Card key={session.sessionId}>
            <CardContent className="pt-6">
              <div className="flex items-center justify-between mb-3">
                <span className="text-sm font-medium text-muted-foreground">
                  {new Date(session.date).toLocaleDateString("en-US", {
                    weekday: "short",
                    month: "short",
                    day: "numeric",
                    year: "numeric",
                  })}
                </span>
                <span className="text-sm font-semibold">
                  {session.sets.length} {session.sets.length === 1 ? "set" : "sets"}
                </span>
              </div>
              <div className="flex flex-wrap gap-2">
                {session.sets.map((set, index) => (
                  <div
                    key={index}
                    className="px-3 py-1.5 bg-zinc-100 dark:bg-zinc-800 rounded-md text-sm font-medium"
                  >
                    {set.reps} × {formatWeight(set.weight, unit)}
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      {hasMore && !showAll && (
        <button
          onClick={() => setShowAll(true)}
          className="w-full py-2 text-sm font-medium text-blue-500 hover:text-blue-600 transition-colors"
        >
          Show all {sessionHistory.length} sessions
        </button>
      )}
    </div>
  );
}
