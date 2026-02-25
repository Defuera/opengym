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

function trendArrow(trend: string): string {
  if (trend === "improving") return "↑";
  if (trend === "declining") return "↓";
  if (trend === "stable") return "→";
  return "";
}

function trendColor(trend: string): string {
  if (trend === "improving") return "text-green-600 dark:text-green-400";
  if (trend === "declining") return "text-red-500 dark:text-red-400";
  return "text-muted-foreground";
}

function weekOverallTrend(sessions: WeekSession[]): string | null {
  if (sessions.length === 0) return null;
  if (!sessions.every((s) => s.summary)) return null;
  const trends = sessions.map((s) => s.summary!.trend);
  if (trends.every((t) => t === "improving")) return "improving";
  if (trends.every((t) => t === "declining")) return "declining";
  if (trends.includes("improving") && !trends.includes("declining")) return "improving";
  if (trends.includes("declining") && !trends.includes("improving")) return "declining";
  return "stable";
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
      className="flex gap-3 overflow-x-auto pb-2"
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
        const overallTrend = weekOverallTrend(week.sessions);

        return (
          <div
            key={week.weekStart}
            style={{ scrollSnapAlign: "start", minWidth: "280px", maxWidth: "280px" }}
            className="rounded-xl border border-border bg-card shadow-sm p-4 flex-shrink-0"
          >
            {/* Week header */}
            <div className="flex items-center justify-between mb-3">
              <span className="font-semibold text-sm">{label}</span>
              {overallTrend && (
                <span className={`text-sm font-medium ${trendColor(overallTrend)}`}>
                  {trendArrow(overallTrend)}
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
                  const exNames = session.exerciseNames.slice(0, 3).join(", ") +
                    (session.exerciseNames.length > 3 ? "…" : "");
                  const hasSummary = !!session.summary;
                  const trend = session.summary?.trend;
                  const arrow = trend ? trendArrow(trend) : "";
                  const color = trend ? trendColor(trend) : "";
                  // Truncate headline to ~30 chars
                  const headlineSnippet = session.summary?.headline
                    ? session.summary.headline.length > 32
                      ? session.summary.headline.slice(0, 30) + "…"
                      : session.summary.headline
                    : null;
                  const hasPR = session.summary?.flags?.includes("pr");

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
                          {hasSummary && headlineSnippet && (
                            <p className={`text-xs mt-0.5 ${color}`}>
                              {arrow} {headlineSnippet}
                              {hasPR && (
                                <span className="ml-1 text-yellow-500">🏆</span>
                              )}
                            </p>
                          )}
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
    </div>
  );
}
