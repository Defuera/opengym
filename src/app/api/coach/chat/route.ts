import { NextRequest, NextResponse } from "next/server";
import { getAI } from "@/lib/ai";
import type { ChatMessage } from "@/lib/ai/types";

export async function POST(req: NextRequest) {
  try {
    // Check if API key is configured
    if (!process.env.OPENAI_API_KEY) {
      return NextResponse.json(
        { error: "AI service not configured. Missing OPENAI_API_KEY." },
        { status: 503 }
      );
    }

    const body = await req.json();
    const { userId, sessionId, messages } = body;

    // Validate input
    if (!messages || !Array.isArray(messages)) {
      return NextResponse.json(
        { error: "Invalid request: messages array required" },
        { status: 400 }
      );
    }

    // Default userId if not provided
    const effectiveUserId = userId ?? "default-user";

    // Get AI services
    const ai = getAI();

    // Call chat.reply
    const result = await ai.chat.reply({
      userId: effectiveUserId,
      sessionId: sessionId ?? null,
      messages: messages as ChatMessage[],
    });

    return NextResponse.json({
      reply: result.reply,
      memoryChanges: result.memoryChanges,
    });
  } catch (error) {
    console.error("Coach chat error:", error);
    return NextResponse.json(
      {
        error: "Failed to get response from coach",
        details: error instanceof Error ? error.message : String(error),
      },
      { status: 500 }
    );
  }
}
