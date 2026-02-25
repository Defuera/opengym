import { v } from "convex/values";
import { action, internalAction, internalMutation, query } from "./_generated/server";
import { api, internal } from "./_generated/api";

/**
 * AI-powered session summary generation.
 * Fetches session data, compares with past sessions, and generates
 * a structured summary stored in the sessionSummaries table.
 */
export const generateSessionSummary = internalAction({
  args: {
    sessionId: v.id("sessions"),
  },
  handler: async (ctx, args) => {
    // Fetch the session with full details via query
    const session = await ctx.runQuery(api.sessions.getWithDetails, {
      id: args.sessionId,
    });

    if (!session) {
      console.warn("generateSessionSummary: session not found", args.sessionId);
      return;
    }

    const userId = session.userId as string;

    // Fetch past completed sessions for comparison (last 30, before current session)
    const pastSessions = await ctx.runQuery(api.sessions.listRecentCompleted, {
      userId: session.userId,
      limit: 30,
    });

    // Only compare against sessions that happened BEFORE this one
    const comparableSessions = pastSessions.filter(
      (s) => s._id !== args.sessionId && s.date < session.date
    );

    // Build a concise text representation for the AI prompt
    const exerciseLines = (session as any).exercises?.map((ex: any) => {
      // Use all sets — status "todo" is the norm since sets aren't individually marked complete
      const completedSets = ex.sets ?? [];
      const totalVol = completedSets.reduce(
        (sum: number, s: any) => sum + s.reps * s.weight,
        0
      );
      const setDescs = completedSets
        .map((s: any) => `${s.reps}×${s.weight}kg`)
        .join(", ");
      return `${ex.name} (${ex.muscleGroup}): ${setDescs || "no completed sets"}, volume=${totalVol}`;
    }) ?? [];

    const pastExerciseSummaries = comparableSessions.slice(0, 5).map((s) => {
      const exes = (s as any).exercises?.map((ex: any) => ex.name).join(", ") ?? "";
      return `${new Date(s.date).toISOString().slice(0, 10)}: ${exes}`;
    });

    const systemPrompt = `You are a fitness analytics engine. Analyze the given workout session and output ONLY valid JSON with this exact structure:
{
  "trend": "improving"|"stable"|"declining"|"insufficient_data",
  "score": <integer 0-100>,
  "headline": "<concise headline, e.g. Strong chest day — Bench Press up 5kg>",
  "highlights": ["<metric highlight 1>", ...],
  "flags": ["pr"|"skipped_sets"|"volume_drop"|"new_exercise"|...],
  "muscleGroups": ["<muscle group name>", ...]
}
Rules:
- trend: compare vs past sessions if available; use insufficient_data if <2 past sessions
- score: 0-100 overall session quality
- headline: max 60 chars
- highlights: 1-4 key metric changes (e.g. "Bench Press: 70kg → 75kg (+7%)")
- flags: only include relevant flags
- muscleGroups: list of muscle groups trained today`;

    const userContent = `Current session (${new Date(session.date).toISOString().slice(0, 10)}):
${exerciseLines.join("\n")}

Past sessions for comparison:
${pastExerciseSummaries.length > 0 ? pastExerciseSummaries.join("\n") : "None available"}`;

    // Use OpenAI via dynamic import (same pattern as aiSessionPlanner.ts)
    const { OpenAIClient } = await import("../src/lib/ai/providers/openaiClient");
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) {
      console.error("generateSessionSummary: OPENAI_API_KEY not set");
      return;
    }

    const client = new OpenAIClient(apiKey);
    let rawContent: string;
    try {
      const result = await client.chat({
        systemPrompt,
        messages: [{ role: "user", content: userContent }],
      });
      rawContent = result.content;
    } catch (err) {
      console.error("generateSessionSummary: OpenAI call failed", err);
      return;
    }

    // Parse JSON response
    let parsed: {
      trend: "improving" | "stable" | "declining" | "insufficient_data";
      score: number;
      headline: string;
      highlights: string[];
      flags: string[];
      muscleGroups: string[];
    } | null = null;

    try {
      // Strip markdown code fences if present
      const json = rawContent.replace(/^```json?\s*/i, "").replace(/```\s*$/i, "").trim();
      parsed = JSON.parse(json);
    } catch {
      console.error("generateSessionSummary: failed to parse AI response", rawContent);
      return;
    }

    if (!parsed) return;

    const validTrends = ["improving", "stable", "declining", "insufficient_data"] as const;
    const trend = validTrends.includes(parsed.trend as any)
      ? parsed.trend
      : "insufficient_data";

    // Store the summary
    await ctx.runMutation(internal.aiSessionSummary.storeSessionSummary, {
      userId,
      sessionId: args.sessionId,
      trend,
      score: Math.max(0, Math.min(100, Math.round(parsed.score ?? 50))),
      headline: parsed.headline ?? "Session complete",
      highlights: Array.isArray(parsed.highlights) ? parsed.highlights : [],
      flags: Array.isArray(parsed.flags) ? parsed.flags : [],
      muscleGroups: Array.isArray(parsed.muscleGroups) ? parsed.muscleGroups : [],
    });
  },
});

export const storeSessionSummary = internalMutation({
  args: {
    userId: v.string(),
    sessionId: v.id("sessions"),
    trend: v.union(
      v.literal("improving"),
      v.literal("stable"),
      v.literal("declining"),
      v.literal("insufficient_data")
    ),
    score: v.number(),
    headline: v.string(),
    highlights: v.array(v.string()),
    flags: v.array(v.string()),
    muscleGroups: v.array(v.string()),
  },
  handler: async (ctx, args) => {
    // Delete any existing summary for this session
    const existing = await ctx.db
      .query("sessionSummaries")
      .withIndex("by_session", (q) => q.eq("sessionId", args.sessionId))
      .first();
    if (existing) {
      await ctx.db.delete(existing._id);
    }

    await ctx.db.insert("sessionSummaries", {
      userId: args.userId,
      sessionId: args.sessionId,
      trend: args.trend,
      score: args.score,
      headline: args.headline,
      highlights: args.highlights,
      flags: args.flags,
      muscleGroups: args.muscleGroups,
      generatedAt: Date.now(),
    });
  },
});


// ---------------------------------------------------------------------------
// Helper to format review prompt from rich AI context
// ---------------------------------------------------------------------------
function buildReviewPrompt(context: any): string {
  const { currentSession, recentSessions, exerciseHistory, recoveryContext, aiMemories } = context;
  const session = currentSession ?? recentSessions?.[0];
  if (!session) return "No session data available.";

  const dateStr = new Date(session.date).toLocaleDateString("en-US", {
    weekday: "long", month: "long", day: "numeric", year: "numeric",
  });

  // Today's session
  const exerciseLines = (session.exercises ?? []).map((ex: any) => {
    const setDescs = (ex.sets ?? []).map((s: any) => `${s.reps}×${s.weight}kg`).join(", ");
    return `- ${ex.name} (${ex.muscleGroup}): ${setDescs || "no sets"}`;
  });

  // Recovery
  const recovery = recoveryContext
    ? `${recoveryContext.daysSinceLastSession ?? "?"} days since last session, ${recoveryContext.sessionsThisWeek} sessions this week`
    : "Recovery data unavailable";

  // Per-exercise history (last 5 occurrences, skip current session date)
  const historyLines: string[] = [];
  for (const ex of (session.exercises ?? [])) {
    const name: string = ex.name;
    const history = (exerciseHistory?.[name] ?? [])
      .filter((h: any) => h.date !== session.date)
      .slice(0, 5);
    if (history.length === 0) {
      historyLines.push(`${name}: no historical data`);
    } else {
      const occurrences = history.map((h: any) => {
        const d = new Date(h.date).toISOString().slice(0, 10);
        return `${d}: top set ${h.topSet.reps}×${h.topSet.weight}kg, vol ${h.totalVolume}kg`;
      }).join(" | ");
      historyLines.push(`${name}: ${occurrences}`);
    }
  }

  // AI memories
  const memoryLines = (aiMemories ?? []).map((m: any) => `- [${m.type}] ${m.key}: ${m.value}`);

  return `
DATE: ${dateStr}

TODAY'S SESSION:
${exerciseLines.join("\n") || "No exercises recorded"}

RECOVERY CONTEXT:
${recovery}

EXERCISE HISTORY (last 5 per exercise, oldest→newest):
${historyLines.join("\n") || "No history available"}

USER GOALS & NOTES:
${memoryLines.join("\n") || "No notes"}

---
Please write a detailed review with these sections:
## Overall Assessment
## Exercise Breakdown
## Next Session Focus
`.trim();
}

// ---------------------------------------------------------------------------
// Internal mutation: upsert reviewText on sessionSummaries
// ---------------------------------------------------------------------------
export const storeReviewText = internalMutation({
  args: {
    sessionId: v.id("sessions"),
    userId: v.string(),
    reviewText: v.string(),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("sessionSummaries")
      .withIndex("by_session", (q) => q.eq("sessionId", args.sessionId))
      .first();

    if (existing) {
      await ctx.db.patch(existing._id, { reviewText: args.reviewText });
    } else {
      // Create minimal summary record with just the review
      await ctx.db.insert("sessionSummaries", {
        userId: args.userId,
        sessionId: args.sessionId,
        trend: "insufficient_data",
        score: 0,
        headline: "Review generated",
        highlights: [],
        flags: [],
        muscleGroups: [],
        generatedAt: Date.now(),
        reviewText: args.reviewText,
      });
    }
  },
});

// ---------------------------------------------------------------------------
// Public action: generate a detailed AI review for a completed session
// ---------------------------------------------------------------------------
export const generateDetailedReview = action({
  args: { sessionId: v.id("sessions") },
  handler: async (ctx, args) => {
    // 1. Get session to find userId
    const session = await ctx.runQuery(api.sessions.getWithDetails, {
      id: args.sessionId,
    });
    if (!session) {
      throw new Error("Session not found: " + args.sessionId);
    }

    const userId = session.userId as string;

    // 2. Build rich context
    const context = await ctx.runQuery(internal.aiUserContext.buildAIContext, {
      userId: session.userId,
      sessionLimit: 10,
      currentSessionId: args.sessionId,
    });

    // 3. Format prompt
    const systemPrompt = `You are a personal strength coach writing a detailed workout review.
Be specific with numbers. Compare to historical data where available. Be honest but motivating.
Use markdown formatting with headers (##). Keep the review concise but insightful (200-400 words).`;

    const userContent = buildReviewPrompt(context);

    // 4. Call OpenAI
    const { OpenAIClient } = await import("../src/lib/ai/providers/openaiClient");
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) {
      throw new Error("OPENAI_API_KEY not set");
    }

    const client = new OpenAIClient(apiKey);
    let reviewText: string;
    try {
      const result = await client.chat({
        systemPrompt,
        messages: [{ role: "user", content: userContent }],
      });
      reviewText = result.content;
    } catch (err) {
      throw new Error("OpenAI call failed: " + String(err));
    }

    // 5. Store reviewText
    await ctx.runMutation(internal.aiSessionSummary.storeReviewText, {
      sessionId: args.sessionId,
      userId,
      reviewText,
    });

    return { reviewText };
  },
});

// ---------------------------------------------------------------------------
// Public query: fetch review text for a session
// ---------------------------------------------------------------------------
export const getSessionReview = query({
  args: { sessionId: v.id("sessions") },
  handler: async (ctx, args) => {
    const summary = await ctx.db
      .query("sessionSummaries")
      .withIndex("by_session", (q) => q.eq("sessionId", args.sessionId))
      .first();
    return summary?.reviewText ?? null;
  },
});
