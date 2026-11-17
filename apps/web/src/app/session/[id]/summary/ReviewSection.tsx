"use client";

import { useQuery, useMutation } from "convex/react";
import { api } from "../../../../../convex/_generated/api";
import { Id } from "../../../../../convex/_generated/dataModel";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { TrendBadge, ScorePill } from "@/components/summary-badges";

interface ReviewSectionProps {
  sessionId: string;
  isCompleted: boolean;
}

export default function ReviewSection({ sessionId, isCompleted }: ReviewSectionProps) {
  const summary = useQuery(api.aiSessionSummary.getSessionSummary, {
    sessionId: sessionId as Id<"sessions">,
  });

  const regenerate = useMutation(api.aiSessionSummary.regenerateReview);

  const handleRegenerate = () => {
    console.log("[ReviewSection] Generate clicked, sessionId:", sessionId);
    regenerate({ sessionId: sessionId as Id<"sessions"> })
      .then(() => console.log("[ReviewSection] regenerateReview mutation sent"))
      .catch((err) => console.error("[ReviewSection] regenerateReview failed:", err));
  };

  // Not yet loaded from Convex
  if (summary === undefined) return null;

  // No summary yet — show generate button for completed sessions
  if (summary === null) {
    if (!isCompleted) return null;
    return (
      <Card className="mt-4">
        <CardContent className="pt-6">
          <div className="flex flex-col items-center gap-3 py-2">
            <p className="text-sm text-muted-foreground text-center">
              Get a personalized AI review of this session.
            </p>
            <Button onClick={handleRegenerate} variant="outline" size="sm">
              Generate AI Review
            </Button>
          </div>
        </CardContent>
      </Card>
    );
  }

  const { headline, score, trend, highlights, exerciseReviews, coachNotes, nextSessionFocus } = summary;

  return (
    <Card className="mt-4">
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <CardTitle className="text-base">AI Coach Review</CardTitle>
          <button
            onClick={handleRegenerate}
            className="text-xs text-muted-foreground underline hover:text-foreground"
          >
            Regenerate
          </button>
        </div>
      </CardHeader>
      <CardContent className="pt-0 space-y-4">
        {/* Headline + Score + Trend */}
        <div className="flex items-start justify-between gap-2">
          <div className="flex-1 min-w-0">
            <p className="text-sm font-medium">{headline}</p>
            <div className="flex items-center gap-2 mt-1">
              <TrendBadge trend={trend} />
            </div>
          </div>
          <ScorePill score={score} />
        </div>

        {/* Highlights */}
        {highlights.length > 0 && (
          <div>
            <p className="text-xs font-medium text-muted-foreground mb-1">Highlights</p>
            <ul className="space-y-1">
              {highlights.map((h, i) => (
                <li key={i} className="text-sm">{h}</li>
              ))}
            </ul>
          </div>
        )}

        {/* Exercise Reviews */}
        {exerciseReviews && exerciseReviews.length > 0 && (
          <div>
            <p className="text-xs font-medium text-muted-foreground mb-2">Exercise Breakdown</p>
            <div className="space-y-2">
              {exerciseReviews.map((ex, i) => (
                <div key={i} className="rounded-lg border border-border p-3">
                  <div className="flex items-center justify-between mb-1">
                    <span className="text-sm font-medium">{ex.name}</span>
                    <div className="flex items-center gap-2">
                      <span className="text-xs text-muted-foreground">{ex.topSet}</span>
                      <TrendBadge trend={ex.trend} />
                    </div>
                  </div>
                  <p className="text-xs text-muted-foreground">{ex.assessment}</p>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Coach Notes */}
        {coachNotes && coachNotes.length > 0 && (
          <div>
            <p className="text-xs font-medium text-muted-foreground mb-1">Coach Notes</p>
            <ul className="space-y-1">
              {coachNotes.map((note, i) => (
                <li key={i} className="text-sm text-muted-foreground">• {note}</li>
              ))}
            </ul>
          </div>
        )}

        {/* Next Session Focus */}
        {nextSessionFocus && (
          <div className="rounded-lg bg-muted/50 p-3">
            <p className="text-xs font-medium text-muted-foreground mb-1">Next Session</p>
            <p className="text-sm">{nextSessionFocus}</p>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
