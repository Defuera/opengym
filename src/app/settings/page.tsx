import { workoutRepository } from "@/lib/repositories";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import UnitSelector from "./unit-selector";

export const dynamic = "force-dynamic";

export default async function SettingsPage() {
  const user = await workoutRepository.getUser("default-user");
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
