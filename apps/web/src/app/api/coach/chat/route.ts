import { NextRequest, NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";
import { api } from "../../../../../convex/_generated/api";
import { Id } from "../../../../../convex/_generated/dataModel";

function getConvexClient() {
  const url = process.env.NEXT_PUBLIC_CONVEX_URL;
  if (!url) throw new Error("NEXT_PUBLIC_CONVEX_URL is not set");
  return new ConvexHttpClient(url);
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { threadId, message } = body;

    if (!threadId || !message) {
      return NextResponse.json(
        { error: "Invalid request: threadId and message required" },
        { status: 400 }
      );
    }

    const convex = getConvexClient();
    const result = await convex.action(api.aiCoach.chat, {
      threadId: threadId as Id<"aiThreads">,
      userMessage: String(message),
    });

    return NextResponse.json(result);
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
