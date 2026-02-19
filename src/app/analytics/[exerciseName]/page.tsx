import Link from "next/link";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
export const dynamic = 'force-dynamic';

export default async function ExerciseDetailPage({
  params,
}: {
  params: Promise<{ exerciseName: string }>;
}) {
  const { exerciseName } = await params;
  const decodedName = decodeURIComponent(exerciseName);

  return (
    <div className="flex min-h-screen flex-col bg-zinc-50 dark:bg-zinc-950">
      <header className="sticky top-0 z-10 border-b bg-white/80 backdrop-blur-lg px-4 py-4 dark:bg-zinc-900/80">
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-bold text-zinc-900 dark:text-zinc-50">
            {decodedName}
          </h1>
          <Link
            href="/analytics"
            className="text-zinc-600 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-50 text-sm font-medium"
          >
            Back
          </Link>
        </div>
      </header>

      <main className="flex-1 px-4 pb-24">
        <div className="mx-auto max-w-2xl space-y-6 pt-6">
          <Card>
            <CardContent className="pt-6 text-center">
              <p className="text-muted-foreground">
                Exercise detail page coming soon
              </p>
            </CardContent>
          </Card>
        </div>
      </main>

      <div className="fixed bottom-0 left-0 right-0 border-t bg-white/95 backdrop-blur-lg p-4 dark:bg-zinc-900/95">
        <div className="mx-auto max-w-2xl">
          <Link href="/analytics">
            <Button size="lg" className="w-full h-14 text-base">
              Back to Analytics
            </Button>
          </Link>
        </div>
      </div>
    </div>
  );
}
