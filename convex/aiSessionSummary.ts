import { v } from "convex/values";
import { action, internalAction, internalQuery } from "./_generated/server";
import { api, internal } from "./_generated/api";
import { Id } from "./_generated/dataModel";

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

    // Fetch past completed sessions for comparison (last 10)
    const pastSessions = await ctx.runQuery(api.sessions.listRecentCompleted, {
      userId: session.userId,
      limit: 10,
    });

    // Filter out the current session from past sessions
    const comparableSessions = pastSessions.filter(
      (s) => s._id !== args.sessionId
    );

    // Build a concise text representation for the AI prompt
    const exerciseLines = (session as any).exercises?.map((ex: any) => {
      const completedSets = ex.sets?.filter(
        (s: any) => s.status === "complete"
      ) ?? ex.sets ?? [];
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

import { internalMutation } from "./_generated/server";

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

/**
 * Internal query: fetch completed sessions for a user that don't yet have a summary.
 */
export const listSessionsWithoutSummaries = internalQuery({
  args: {
    userId: v.id("users"),
  },
  handler: async (ctx, args) => {
    // Fetch completed sessions for this user
    const sessions = await ctx.db
      .query("sessions")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .filter((q) => q.eq(q.field("status"), "completed"))
      .collect();

    // Check each session for an existing summary using the by_session index
    const result = [];
    for (const session of sessions) {
      const existing = await ctx.db
        .query("sessionSummaries")
        .withIndex("by_session", (q) => q.eq("sessionId", session._id))
        .first();
      if (!existing) {
        result.push(session);
      }
    }

    return result;
  },
});

/**
 * Public action: backfill AI summaries for all completed sessions that don't have one yet.
 * Can be triggered from the Convex dashboard or the Settings page.
 * Requires a valid userId to ensure only authenticated users can trigger it.
 */
export const backfillSessionSummaries = action({
  args: {
    userId: v.id("users"),
  },
  handler: async (ctx, args): Promise<{ generated: number; errors: number }> => {
    // Verify the user exists
    const user = await ctx.runQuery(api.users.get, { id: args.userId });
    if (!user) {
      throw new Error("Unauthorized: invalid user");
    }

    const sessions = await ctx.runQuery(
      internal.aiSessionSummary.listSessionsWithoutSummaries,
      { userId: args.userId }
    );

    let generated = 0;
    let errors = 0;

    for (const session of sessions) {
      try {
        await ctx.runAction(internal.aiSessionSummary.generateSessionSummary, {
          sessionId: session._id,
        });
        generated++;
      } catch (err) {
        console.error("backfillSessionSummaries: failed for session", session._id, err);
        errors++;
      }
    }

    console.log(`backfillSessionSummaries: generated=${generated}, errors=${errors}`);
    return { generated, errors };
  },
});
