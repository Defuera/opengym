import { workoutRepository } from "@/lib/repositories";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import Link from "next/link";
import UnitSelector from "./unit-selector";

export const dynamic = "force-dynamic";

export default async function SettingsPage() {
  const user = await workoutRepository.getUser("default-user");
  const currentUnit = user?.unit ?? "metric";

  return (
    <div className="flex min-h-screen flex-col bg-zinc-50 dark:bg-zinc-950">
      <header className="sticky top-0 z-10 border-b bg-white/80 backdrop-blur-lg px-4 py-4 dark:bg-zinc-900/80">
        <div className="flex items-center gap-3">
          <Link
            href="/"
            className="text-zinc-600 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-50"
          >
            ←
          </Link>
          <h1 className="text-xl font-bold text-zinc-900 dark:text-zinc-50">
            Settings
          </h1>
        </div>
      </header>

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
