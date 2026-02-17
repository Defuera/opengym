"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { Button } from "@/components/ui/button";

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
    <Button
      onClick={handleStartSession}
      disabled={isCreating}
      size="lg"
      className="h-14 w-full text-base"
    >
      {isCreating ? "Starting..." : "Start New Session"}
    </Button>
  );
}
