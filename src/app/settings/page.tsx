"use client";

import { useState } from "react";
import { useQuery, useAction } from "convex/react";
import { api } from "../../../convex/_generated/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import UnitSelector from "./unit-selector";

export default function SettingsPage() {
  const user = useQuery(api.users.getDefaultUser, {});
  const backfillSummaries = useAction(api.aiSessionSummary.backfillSessionSummaries);
  const [backfillStatus, setBackfillStatus] = useState<string | null>(null);
  const [backfillLoading, setBackfillLoading] = useState(false);

  const handleBackfill = async () => {
    setBackfillLoading(true);
    setBackfillStatus(null);
    try {
      const result = await backfillSummaries({});
      setBackfillStatus(`Done! Generated ${result.generated} summaries${result.errors > 0 ? `, ${result.errors} errors` : ""}.`);
    } catch (err) {
      setBackfillStatus(`Error: ${err instanceof Error ? err.message : String(err)}`);
    } finally {
      setBackfillLoading(false);
    }
  };

  if (user === undefined) {
    return (
      <div className="flex min-h-screen flex-col bg-zinc-50 dark:bg-zinc-950">
        <main className="flex-1 px-4 pb-24">
          <div className="mx-auto max-w-2xl space-y-6 pt-6">
            <Card>
              <CardHeader>
                <CardTitle className="text-base font-semibold">
                  Weight Units
                </CardTitle>
              </CardHeader>
              <CardContent>
                <p className="text-sm text-zinc-600 dark:text-zinc-400">Loading...</p>
              </CardContent>
            </Card>
          </div>
        </main>
      </div>
    );
  }

  const currentUnit = user?.unit ?? "metric";

  return (
    <div className="flex min-h-screen flex-col bg-zinc-50 dark:bg-zinc-950">
      <main className="flex-1 px-4 pb-24">
        <div className="mx-auto max-w-2xl space-y-6 pt-6">
          <Card>
            <CardHeader>
              <CardTitle className="text-base font-semibold">
                Weight Units
              </CardTitle>
            </CardHeader>
            <CardContent>
              <UnitSelector currentUnit={currentUnit} />
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-base font-semibold">
                AI Summaries
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <p className="text-sm text-zinc-600 dark:text-zinc-400">
                Generate AI summaries for all past workout sessions that don&apos;t have one yet.
              </p>
              <button
                onClick={handleBackfill}
                disabled={backfillLoading}
                className="rounded-md bg-zinc-900 px-4 py-2 text-sm font-medium text-white hover:bg-zinc-700 disabled:opacity-50 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-zinc-300"
              >
                {backfillLoading ? "Generating…" : "Generate AI Summaries"}
              </button>
              {backfillStatus && (
                <p className="text-sm text-zinc-600 dark:text-zinc-400">{backfillStatus}</p>
              )}
            </CardContent>
          </Card>
        </div>
      </main>
    </div>
  );
}
