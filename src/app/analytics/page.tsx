import { workoutRepository } from "@/lib/repositories";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { formatWeight } from "@/lib/units";
import Link from "next/link";
import { AnalyticsCharts } from "./analytics-charts";
export const dynamic = 'force-dynamic';

export default async function AnalyticsPage() {
  const analytics = await workoutRepository.getAnalytics("default-user");
  const exerciseAnalytics = await workoutRepository.getExerciseAnalytics("default-user");
  const user = await workoutRepository.getUser("default-user");
  const unit = user?.unit ?? "metric";

  // Calculate week-over-week change
  const weekChange =
    analytics.lastWeek.totalVolume > 0
      ? ((analytics.currentWeek.totalVolume - analytics.lastWeek.totalVolume) /
          analytics.lastWeek.totalVolume) *
        100
      : 0;

  return (
    <div className="flex min-h-screen flex-col bg-zinc-50 dark:bg-zinc-950">
      <header className="sticky top-0 z-10 border-b bg-white/80 backdrop-blur-lg px-4 py-4 dark:bg-zinc-900/80">
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-bold text-zinc-900 dark:text-zinc-50">
            Analytics
          </h1>
          <Link
            href="/"
            className="text-zinc-600 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-50 text-sm font-medium"
          >
            Home
          </Link>
        </div>
      </header>

      <main className="flex-1 px-4 pb-24">
        <div className="mx-auto max-w-2xl space-y-6 pt-6">
          {/* Last Session Card */}
          {analytics.lastSession && (
            <Card>
              <CardHeader>
                <CardTitle className="text-base">Last Session</CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                <div className="flex items-center justify-between">
                  <span className="text-sm text-muted-foreground">
                    {new Date(analytics.lastSession.date).toLocaleDateString("en-US", {
                      weekday: "short",
                      month: "short",
                      day: "numeric",
                    })}
                  </span>
                  <span className="font-medium">
                    {formatWeight(analytics.lastSession.volume, unit)}
                  </span>
                </div>
                <div className="text-sm text-muted-foreground">
                  {analytics.lastSession.exercises.join(", ")}
                </div>
                {analytics.lastSession.comparison && (
                  <div className="flex items-center gap-2 text-sm">
                    <span className="text-muted-foreground">vs similar session:</span>
                    {analytics.lastSession.comparison.percentChange > 0 ? (
                      <Badge variant="default" className="bg-green-600">
                        ↑ {Math.abs(Math.round(analytics.lastSession.comparison.percentChange))}%
                      </Badge>
                    ) : analytics.lastSession.comparison.percentChange < 0 ? (
                      <Badge variant="secondary">
                        ↓ {Math.abs(Math.round(analytics.lastSession.comparison.percentChange))}%
                      </Badge>
                    ) : (
                      <Badge variant="secondary">→ 0%</Badge>
                    )}
                  </div>
                )}
              </CardContent>
            </Card>
          )}

          {/* Weekly Stats */}
          <div className="grid grid-cols-2 gap-3">
            <Card>
              <CardContent className="pt-6">
                <p className="text-sm text-muted-foreground mb-1">This Week</p>
                <p className="text-2xl font-bold">
                  {analytics.currentWeek.sessionCount}
                </p>
                <p className="text-xs text-muted-foreground mt-1">
                  {analytics.currentWeek.sessionCount === 1 ? "session" : "sessions"}
                </p>
                <p className="text-lg font-semibold mt-2">
                  {formatWeight(analytics.currentWeek.totalVolume, unit)}
                </p>
                {weekChange !== 0 && (
                  <div className="mt-2">
                    {weekChange > 0 ? (
                      <Badge variant="default" className="bg-green-600 text-xs">
                        ↑ {Math.abs(Math.round(weekChange))}%
                      </Badge>
                    ) : (
                      <Badge variant="secondary" className="text-xs">
                        ↓ {Math.abs(Math.round(weekChange))}%
                      </Badge>
                    )}
                  </div>
                )}
              </CardContent>
            </Card>

            <Card>
              <CardContent className="pt-6">
                <p className="text-sm text-muted-foreground mb-1">Last Week</p>
                <p className="text-2xl font-bold">
                  {analytics.lastWeek.sessionCount}
                </p>
                <p className="text-xs text-muted-foreground mt-1">
                  {analytics.lastWeek.sessionCount === 1 ? "session" : "sessions"}
                </p>
                <p className="text-lg font-semibold mt-2">
                  {formatWeight(analytics.lastWeek.totalVolume, unit)}
                </p>
              </CardContent>
            </Card>
          </div>

          {/* Monthly Trend Chart */}
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Last 4 Weeks</CardTitle>
            </CardHeader>
            <CardContent>
              <AnalyticsCharts data={analytics.weeklyTrend} unit={unit} />
            </CardContent>
          </Card>

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
                                {exercise.sessionCount} {exercise.sessionCount === 1 ? "session" : "sessions"}
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
