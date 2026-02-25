"use client";

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";

type SessionSummary = {
  trend: string;
  score: number;
  headline: string;
  highlights: string[];
  flags: string[];
  muscleGroups: string[];
  generatedAt: number;
};

type WeekSession = {
  sessionId: string;
  date: number;
  exerciseNames: string[];
  summary?: SessionSummary;
};

type WeekData = {
  weekStart: number;
  weekEnd: number;
  sessions: WeekSession[];
};

interface WeeklyCarouselProps {
  weeks: WeekData[];
}

function formatWeekLabel(weekStart: number, index: number): string {
  if (index === 0) return "This Week";
  if (index === 1) return "Last Week";
  const start = new Date(weekStart);
  const end = new Date(weekStart + 6 * 24 * 60 * 60 * 1000);
  const startStr = start.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
  });
  const endStr = end.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
  });
  return `${startStr}–${endStr}`;
}

function formatDayAbbrev(date: number): string {
  return new Date(date).toLocaleDateString("en-US", {
    weekday: "short",
  });
}

function capitalize(s: string): string {
  if (!s) return s;
  return s.charAt(0).toUpperCase() + s.slice(1);
}

function formatMuscleGroups(muscleGroups: string[]): string {
  return muscleGroups.map(capitalize).join(" · ");
}

function scoreToTen(score: number): number {
  return Math.round(score / 10);
}

function scorePillClass(score10: number): string {
  if (score10 >= 7) return "bg-green-100 text-green-700 dark:bg-green-900/50 dark:text-green-300";
  if (score10 >= 4) return "bg-amber-100 text-amber-700 dark:bg-amber-900/50 dark:text-amber-300";
  return "bg-red-100 text-red-700 dark:bg-red-900/50 dark:text-red-300";
}

function weekAvgScore(sessions: WeekSession[]): number | null {
  const withSummary = sessions.filter((s) => s.summary);
  if (withSummary.length === 0) return null;
  const total = withSummary.reduce((sum, s) => sum + scoreToTen(s.summary!.score), 0);
  return Math.round(total / withSummary.length);
}

export function WeeklyCarousel({ weeks }: WeeklyCarouselProps) {
  const scrollRef = useRef<HTMLDivElement>(null);
  const router = useRouter();

  // Auto-scroll to the rightmost (current week) card when weeks data is ready
  useEffect(() => {
    if (scrollRef.current && weeks.length) {
      scrollRef.current.scrollLeft = scrollRef.current.scrollWidth;
    }
  }, [weeks.length]);

  // Render oldest week first, current week last (rightmost)
  const reversedWeeks = [...weeks].reverse();

  return (
    <div
      ref={scrollRef}
      className="flex gap-3 overflow-x-auto pb-2 px-4"
        style={{
          scrollSnapType: "x mandatory",
          WebkitOverflowScrolling: "touch",
          scrollbarWidth: "none",
          msOverflowStyle: "none",
        }}
      >
        {reversedWeeks.map((week, reversedIndex) => {
          // Map reversed index back to original index (0 = current week, 1 = last week, ...)
          const index = reversedWeeks.length - 1 - reversedIndex;
          const label = formatWeekLabel(week.weekStart, index);
          const avgScore = weekAvgScore(week.sessions);

          return (
            <div
              key={week.weekStart}
              style={{ scrollSnapAlign: "start", minWidth: "280px", maxWidth: "280px" }}
              className="rounded-xl border border-border bg-card shadow-sm p-4 flex-shrink-0"
            >
              {/* Week header */}
              <div className="flex items-center justify-between mb-3">
                <span className="font-semibold text-sm">{label}</span>
                {avgScore !== null && (
                  <span className="text-xs font-medium text-muted-foreground">
                    ⭐ {avgScore}/10
                  </span>
                )}
              </div>

              {/* Sessions */}
              {week.sessions.length === 0 ? (
                <p className="text-sm text-muted-foreground">No sessions this week</p>
              ) : (
                <div className="space-y-2">
                  {week.sessions.map((session) => {
                    const day = formatDayAbbrev(session.date);
                    const hasSummary = !!session.summary;

                    if (hasSummary && session.summary) {
                      const score10 = scoreToTen(session.summary.score);
                      const muscleLabel = session.summary.muscleGroups.length > 0
                        ? formatMuscleGroups(session.summary.muscleGroups)
                        : null;

                      return (
                        <button
                          key={session.sessionId}
                          className="w-full text-left rounded-lg px-2 py-2 hover:bg-muted/50 active:bg-muted transition-colors"
                          onClick={() => router.push(`/session/${session.sessionId}`)}
                        >
                          <div className="flex items-start gap-2">
                            {/* Day */}
                            <span className="text-xs font-medium text-muted-foreground w-8 shrink-0 pt-0.5">
                              {day}
                            </span>
                            {/* Muscle groups + headline */}
                            <div className="flex-1 min-w-0">
                              {muscleLabel && (
                                <p className="text-xs font-medium truncate">{muscleLabel}</p>
                              )}
                              <p className="text-xs text-muted-foreground mt-0.5 truncate">
                                {session.summary.headline}
                              </p>
                            </div>
                            {/* Score pill */}
                            <span
                              className={`text-xs font-semibold px-1.5 py-0.5 rounded-full shrink-0 ${scorePillClass(score10)}`}
                            >
                              {score10}/10
                            </span>
                          </div>
                        </button>
                      );
                    }

                    // Fallback: no summary — show day + exercise names
                    const exNames =
                      session.exerciseNames.slice(0, 3).join(", ") +
                      (session.exerciseNames.length > 3 ? "…" : "");

                    return (
                      <button
                        key={session.sessionId}
                        className="w-full text-left rounded-lg px-2 py-2 hover:bg-muted/50 active:bg-muted transition-colors"
                        onClick={() => router.push(`/session/${session.sessionId}`)}
                      >
                        <div className="flex items-start gap-2">
                          <span className="text-xs font-medium text-muted-foreground w-8 shrink-0 pt-0.5">
                            {day}
                          </span>
                          <div className="flex-1 min-w-0">
                            <p className="text-xs font-medium truncate">{exNames}</p>
                          </div>
                        </div>
                      </button>
                    );
                  })}
                </div>
              )}
            </div>
          );
        })}
        {/* Trailing spacer so last card aligns with page padding */}
        <div className="w-4 shrink-0" />
    </div>
  );
}
