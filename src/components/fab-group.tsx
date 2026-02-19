"use client";

import { usePathname, useRouter } from "next/navigation";
import { useState } from "react";

export function FabGroup() {
  const pathname = usePathname();
  const router = useRouter();
  const [isCreating, setIsCreating] = useState(false);

  // Hide FABs on session pages and coach page
  const shouldHide = pathname.startsWith("/session") || pathname === "/coach";
  if (shouldHide) return null;

  // Check if AI is enabled
  const aiEnabled = process.env.NEXT_PUBLIC_AI_ENABLED === "true";

  const handleStartSession = async () => {
    if (isCreating) return;

    setIsCreating(true);
    try {
      const response = await fetch("/api/sessions/propose", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ userId: "default-user" }),
      });

      if (!response.ok) {
        throw new Error("Failed to create session");
      }

      const session = await response.json();
      router.push(`/session/${session.id}`);
    } catch (error) {
      console.error("Error creating session:", error);
      setIsCreating(false);
    }
  };

  return (
    <div className="fixed bottom-6 right-6 flex flex-col-reverse items-end gap-3 z-50">
      {/* Primary FAB - Start Session */}
      <button
        onClick={handleStartSession}
        disabled={isCreating}
        className="flex h-16 w-16 items-center justify-center rounded-full bg-blue-600 text-white shadow-lg transition-all hover:bg-blue-700 active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed"
        aria-label="Start new session"
      >
        {isCreating ? (
          <svg
            className="animate-spin h-6 w-6"
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
          >
            <circle
              className="opacity-25"
              cx="12"
              cy="12"
              r="10"
              stroke="currentColor"
              strokeWidth="4"
            />
            <path
              className="opacity-75"
              fill="currentColor"
              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
            />
          </svg>
        ) : (
          <svg
            width="28"
            height="28"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2.5"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <line x1="12" y1="5" x2="12" y2="19" />
            <line x1="5" y1="12" x2="19" y2="12" />
          </svg>
        )}
      </button>

      {/* Secondary FAB - AI Coach (only if enabled) */}
      {aiEnabled && (
        <button
          onClick={() => router.push("/coach")}
          className="flex h-12 w-12 items-center justify-center rounded-full bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-50 shadow-lg border border-zinc-200 dark:border-zinc-700 transition-all hover:shadow-xl active:scale-95"
          aria-label="AI Coach"
        >
          <span className="text-xl">💬</span>
        </button>
      )}
    </div>
  );
}
