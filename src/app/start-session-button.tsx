"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

export default function StartSessionButton() {
  const router = useRouter();
  const [isCreating, setIsCreating] = useState(false);

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
    <button
      onClick={handleStartSession}
      disabled={isCreating}
      className="flex h-14 w-full items-center justify-center rounded-lg bg-blue-600 px-6 text-base font-semibold text-white transition-colors hover:bg-blue-700 active:bg-blue-800 disabled:cursor-not-allowed disabled:opacity-50"
    >
      {isCreating ? "Starting..." : "Start New Session"}
    </button>
  );
}
