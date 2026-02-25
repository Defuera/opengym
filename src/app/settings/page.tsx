"use client";

import { useQuery } from "convex/react";
import { api } from "../../../convex/_generated/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import UnitSelector from "./unit-selector";

export default function SettingsPage() {
  const user = useQuery(api.users.getDefaultUser, {});

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
        </div>
      </main>
    </div>
  );
}
