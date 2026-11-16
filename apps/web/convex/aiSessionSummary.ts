import { v } from "convex/values";
import { internalAction, internalMutation, mutation, query } from "./_generated/server";
import { api, internal } from "./_generated/api";

/**
 * AI-powered session review generation.
 * Uses centralized context from aiContext.ts to produce
 * a structured JSON review stored in sessionSummaries.
 */

// ---------------------------------------------------------------------------
// Core: generate structured session review
// ---------------------------------------------------------------------------
export const generateSessionSummary = internalAction({
  args: {
    sessionId: v.id("sessions"),
  },
  handler: async (ctx, args) => {
    console.log("[generateSessionSummary] started for", args.sessionId);

    const session = await ctx.runQuery(api.sessions.getWithDetails, {
      id: args.sessionId,
    });

    if (!session) {
      console.warn("[generateSessionSummary] session not found", args.sessionId);
      return;
    }

    const userId = session.userId as string;

    // Build context via centralized module (CSV format, current session marked as TODAY)
    const userContent = await ctx.runQuery(internal.aiContext.buildContext, {
      userId: session.userId,
      sessionLimit: 10,
      currentSessionId: args.sessionId,
    });
    console.log("[generateSessionSummary] context:\n", userContent);

    if (!userContent) {
      console.warn("[generateSessionSummary] empty context for", args.sessionId);
      return;
    }

    const systemPrompt = `You are a strength coach. Analyze the workout data and output ONLY valid JSON:
{
  "trend": "improving"|"stable"|"declining"|"insufficient_data",
  "score": 0-100,
  "headline": "<max 60 chars, specific>",
  "highlights": ["<metric change with numbers>", ...],
  "muscleGroups": ["<group>", ...],
  "exerciseReviews": [
    { "name": "<name>", "assessment": "<1 sentence>", "trend": "improving"|"stable"|"declining"|"new", "topSet": "<e.g. 6x75>" }
  ],
  "coachNotes": ["<actionable tip>", ...],
  "nextSessionFocus": "<1 sentence>"
}
Rules:
- The row marked TODAY is the session to review; other rows are history for comparison
- trend: compare vs history; use insufficient_data if <2 past sessions
- score: 0-100 session quality (volume, progression, balance)
- headline: max 60 chars, motivating
- highlights: 1-3 key metric changes with numbers
- exerciseReviews: one per TODAY exercise, assessment is ONE sentence
- coachNotes: 1-2 max, actionable
- nextSessionFocus: brief recommendation`;

    const { OpenAIClient } = await import("../src/lib/ai/providers/openaiClient");
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) {
      console.error("[generateSessionSummary] OPENAI_API_KEY not set");
      return;
    }

    const client = new OpenAIClient(apiKey);
    let rawContent: string;
    try {
      console.log("[generateSessionSummary] calling OpenAI...");
      const result = await client.chat({
        systemPrompt,
        messages: [{ role: "user", content: userContent }],
      });
      rawContent = result.content;
      console.log("[generateSessionSummary] OpenAI response length:", rawContent.length);
    } catch (err) {
      console.error("[generateSessionSummary] OpenAI call failed", err);
      return;
    }

    // Parse JSON response
    let parsed: any = null;
    try {
      const json = rawContent.replace(/^```json?\s*/i, "").replace(/```\s*$/i, "").trim();
      parsed = JSON.parse(json);
      console.log("[generateSessionSummary] parsed OK, trend:", parsed.trend, "score:", parsed.score);
    } catch {
      console.error("[generateSessionSummary] failed to parse AI response", rawContent);
      return;
    }

    if (!parsed) return;

    const validTrends = ["improving", "stable", "declining", "insufficient_data"] as const;
    const trend = validTrends.includes(parsed.trend)
      ? parsed.trend
      : "insufficient_data";

    // Validate exerciseReviews
    const exerciseReviews = Array.isArray(parsed.exerciseReviews)
      ? parsed.exerciseReviews.map((r: any) => ({
          name: String(r.name ?? ""),
          assessment: String(r.assessment ?? ""),
          trend: String(r.trend ?? "stable"),
          topSet: String(r.topSet ?? ""),
        }))
      : [];

    await ctx.runMutation(internal.aiSessionSummary.storeSessionSummary, {
      userId,
      sessionId: args.sessionId,
      trend,
      score: Math.max(0, Math.min(100, Math.round(parsed.score ?? 50))),
      headline: parsed.headline ?? "Session complete",
      highlights: Array.isArray(parsed.highlights) ? parsed.highlights : [],
      muscleGroups: Array.isArray(parsed.muscleGroups) ? parsed.muscleGroups : [],
      exerciseReviews,
      coachNotes: Array.isArray(parsed.coachNotes) ? parsed.coachNotes : [],
      nextSessionFocus: typeof parsed.nextSessionFocus === "string" ? parsed.nextSessionFocus : undefined,
    });
    console.log("[generateSessionSummary] stored summary for", args.sessionId);
  },
});

// ---------------------------------------------------------------------------
// Store summary (internal mutation)
// ---------------------------------------------------------------------------
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
    muscleGroups: v.array(v.string()),
    exerciseReviews: v.array(
      v.object({
        name: v.string(),
        assessment: v.string(),
        trend: v.string(),
        topSet: v.string(),
      })
    ),
    coachNotes: v.array(v.string()),
    nextSessionFocus: v.optional(v.string()),
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
      muscleGroups: args.muscleGroups,
      exerciseReviews: args.exerciseReviews,
      coachNotes: args.coachNotes,
      nextSessionFocus: args.nextSessionFocus,
      generatedAt: Date.now(),
    });
  },
});

// ---------------------------------------------------------------------------
// Public query: fetch full summary for a session
// ---------------------------------------------------------------------------
export const getSessionSummary = query({
  args: { sessionId: v.id("sessions") },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("sessionSummaries")
      .withIndex("by_session", (q) => q.eq("sessionId", args.sessionId))
      .first();
  },
});

// ---------------------------------------------------------------------------
// Public mutation: regenerate review (schedules the internal action)
// ---------------------------------------------------------------------------
export const regenerateReview = mutation({
  args: { sessionId: v.id("sessions") },
  handler: async (ctx, args) => {
    console.log("[regenerateReview] scheduling generateSessionSummary for", args.sessionId);
    await ctx.scheduler.runAfter(0, internal.aiSessionSummary.generateSessionSummary, {
      sessionId: args.sessionId,
    });
  },
});
