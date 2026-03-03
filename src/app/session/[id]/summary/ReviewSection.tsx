"use client";

import { useState } from "react";
import { useQuery, useAction } from "convex/react";
import { api } from "../../../../../convex/_generated/api";
import { Id } from "../../../../../convex/_generated/dataModel";
import ReactMarkdown from "react-markdown";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

interface ReviewSectionProps {
  sessionId: string;
  isCompleted: boolean;
}

export default function ReviewSection({ sessionId, isCompleted }: ReviewSectionProps) {
  const [isGenerating, setIsGenerating] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const reviewText = useQuery(api.aiSessionSummary.getSessionReview, {
    sessionId: sessionId as Id<"sessions">,
  });

  const generateReview = useAction(api.aiSessionSummary.generateDetailedReview);

  const handleGenerate = async () => {
    setIsGenerating(true);
    setError(null);
    try {
      await generateReview({ sessionId: sessionId as Id<"sessions"> });
    } catch (err) {
      setError("Failed to generate review. Please try again.");
      console.error("Review generation failed:", err);
    } finally {
      setIsGenerating(false);
    }
  };

  // Not yet loaded
  if (reviewText === undefined) return null;

  // Review exists: show it
  if (reviewText) {
    return (
      <Card className="mt-4">
        <CardHeader className="pb-3">
          <div className="flex items-center justify-between">
            <CardTitle className="text-base">AI Coach Review</CardTitle>
            <button
              onClick={handleGenerate}
              disabled={isGenerating}
              className="text-xs text-muted-foreground underline hover:text-foreground disabled:opacity-50"
            >
              {isGenerating ? "Regenerating…" : "Regenerate"}
            </button>
          </div>
        </CardHeader>
        <CardContent className="pt-0">
          {isGenerating ? (
            <div className="flex items-center gap-2 text-sm text-muted-foreground py-4">
              <span className="animate-spin inline-block w-4 h-4 border-2 border-current border-t-transparent rounded-full" />
              Generating review…
            </div>
          ) : (
            <div className="prose prose-sm dark:prose-invert max-w-none text-sm">
              <ReactMarkdown>{reviewText}</ReactMarkdown>
            </div>
          )}
          {error && <p className="text-xs text-red-500 mt-2">{error}</p>}
        </CardContent>
      </Card>
    );
  }

  // No review yet: show Generate button (only for completed sessions)
  if (!isCompleted) return null;

  return (
    <Card className="mt-4">
      <CardContent className="pt-6">
        <div className="flex flex-col items-center gap-3 py-2">
          <p className="text-sm text-muted-foreground text-center">
            Get a personalized AI review of this session comparing it to your history.
          </p>
          {isGenerating ? (
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <span className="animate-spin inline-block w-4 h-4 border-2 border-current border-t-transparent rounded-full" />
              Generating review…
            </div>
          ) : (
            <Button onClick={handleGenerate} variant="outline" size="sm">
              ✨ Generate AI Review
            </Button>
          )}
          {error && <p className="text-xs text-red-500">{error}</p>}
        </div>
      </CardContent>
    </Card>
  );
}
