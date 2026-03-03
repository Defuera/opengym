import { NextRequest, NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";
import { api } from "../../../../../convex/_generated/api";

function getConvexClient() {
  const url = process.env.NEXT_PUBLIC_CONVEX_URL;
  if (!url) throw new Error("NEXT_PUBLIC_CONVEX_URL is not set");
  return new ConvexHttpClient(url);
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { messages } = body;

    if (!messages || !Array.isArray(messages)) {
      return NextResponse.json(
        { error: "Invalid request: messages array required" },
        { status: 400 }
      );
    }

    const convex = getConvexClient();
    const reply = await convex.action(api.aiCoach.chat, {
      messages: messages.map((m: { role: string; content: string }) => ({
        role: String(m.role),
        content: String(m.content ?? ""),
      })),
    });

    return NextResponse.json({
      reply: { role: "assistant", content: reply },
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
