import { NextRequest, NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";
import { api } from "../../../../../convex/_generated/api";

// ---------------------------------------------------------------------------
// Convex client (server-side)
// ---------------------------------------------------------------------------
function getConvexClient() {
  const url = process.env.NEXT_PUBLIC_CONVEX_URL;
  if (!url) throw new Error("NEXT_PUBLIC_CONVEX_URL is not set");
  return new ConvexHttpClient(url);
}

// ---------------------------------------------------------------------------
// OpenAI tool definitions
// ---------------------------------------------------------------------------
const COACH_TOOLS = [
  {
    type: "function" as const,
    function: {
      name: "get_recent_sessions",
      description:
        "Get the user's recent workout sessions with exercise names. Always call this before answering questions about workout history.",
      parameters: {
        type: "object",
        properties: {
          limit: { type: "number", description: "Number of sessions to return (default 10)" },
        },
        required: [],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "get_session_detail",
      description: "Get full detail of a specific session including all sets and weights.",
      parameters: {
        type: "object",
        properties: {
          session_id: { type: "string", description: "The session ID" },
        },
        required: ["session_id"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "get_exercise_history",
      description:
        "Get history of a specific exercise across all sessions – useful for tracking progress.",
      parameters: {
        type: "object",
        properties: {
          exercise_name: { type: "string", description: "Name of the exercise" },
          limit: { type: "number", description: "Max number of sessions to include" },
        },
        required: ["exercise_name"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "get_exercises",
      description: "Get all unique exercises the user has ever done (their exercise catalog).",
      parameters: {
        type: "object",
        properties: {},
        required: [],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "create_session",
      description: "Create a new workout session on behalf of the user.",
      parameters: {
        type: "object",
        properties: {
          name: { type: "string", description: "Name/title of the session, e.g. 'Push Day'" },
        },
        required: ["name"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "log_set",
      description: "Log a completed set for an exercise in an active session.",
      parameters: {
        type: "object",
        properties: {
          session_id: { type: "string", description: "The session ID" },
          exercise_id: { type: "string", description: "The exercise ID" },
          reps: { type: "number", description: "Number of reps performed" },
          weight: { type: "number", description: "Weight used (kg or lb)" },
        },
        required: ["session_id", "exercise_id", "reps", "weight"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "complete_session",
      description: "Mark a workout session as completed.",
      parameters: {
        type: "object",
        properties: {
          session_id: { type: "string", description: "The session ID to complete" },
        },
        required: ["session_id"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "add_exercise",
      description: "Add a new exercise to an existing session.",
      parameters: {
        type: "object",
        properties: {
          session_id: { type: "string", description: "The session ID" },
          name: { type: "string", description: "Exercise name" },
          muscle_group: { type: "string", description: "Muscle group targeted" },
        },
        required: ["session_id", "name", "muscle_group"],
      },
    },
  },
] as const;

type ToolName =
  | "get_recent_sessions"
  | "get_session_detail"
  | "get_exercise_history"
  | "get_exercises"
  | "create_session"
  | "log_set"
  | "complete_session"
  | "add_exercise";

// ---------------------------------------------------------------------------
// Execute a single tool call against Convex
// ---------------------------------------------------------------------------
async function executeTool(
  convex: ConvexHttpClient,
  userId: string,
  toolName: ToolName,
  args: Record<string, unknown>
): Promise<unknown> {
  switch (toolName) {
    case "get_recent_sessions":
      return convex.query(api.aiTools.getRecentSessions, {
        userId,
        limit: (args.limit as number) ?? 10,
      });

    case "get_session_detail":
      return convex.query(api.aiTools.getSessionDetail, {
        userId,
        sessionId: args.session_id as string,
      });

    case "get_exercise_history":
      return convex.query(api.aiTools.getExerciseHistory, {
        userId,
        exerciseName: args.exercise_name as string,
        limit: (args.limit as number) ?? 20,
      });

    case "get_exercises":
      return convex.query(api.aiTools.getExercises, { userId });

    case "create_session":
      return convex.mutation(api.aiTools.createSession, {
        userId,
        name: args.name as string,
      });

    case "log_set":
      return convex.mutation(api.aiTools.logSet, {
        userId,
        sessionId: args.session_id as string,
        exerciseId: args.exercise_id as string,
        reps: args.reps as number,
        weight: args.weight as number,
      });

    case "complete_session":
      return convex.mutation(api.aiTools.completeSession, {
        userId,
        sessionId: args.session_id as string,
      });

    case "add_exercise":
      return convex.mutation(api.aiTools.addExercise, {
        userId,
        sessionId: args.session_id as string,
        name: args.name as string,
        muscleGroup: args.muscle_group as string,
      });

    default:
      return { error: `Unknown tool: ${toolName}` };
  }
}

// ---------------------------------------------------------------------------
// System prompt
// ---------------------------------------------------------------------------
const SYSTEM_PROMPT = `You are a personal fitness coach assistant for OpenGym. You have full access to the user's workout data.

When asked about their history, sessions, or exercises — always look it up first using the available tools before answering. Never make up data.

You can also:
- Create new workout sessions
- Log sets with reps and weight  
- Add exercises to sessions
- Mark sessions as complete

Be concise, encouraging, and data-driven. Use **markdown** for formatting — bold for key numbers, bullet lists for exercise breakdowns, and headings for structure when helpful.`;

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------
export async function POST(req: NextRequest) {
  try {
    if (!process.env.OPENAI_API_KEY) {
      return NextResponse.json(
        { error: "AI service not configured. Missing OPENAI_API_KEY." },
        { status: 503 }
      );
    }

    const body = await req.json();
    const { userId, messages } = body;

    if (!messages || !Array.isArray(messages)) {
      return NextResponse.json(
        { error: "Invalid request: messages array required" },
        { status: 400 }
      );
    }

    const effectiveUserId = userId ?? "default-user";
    const convex = getConvexClient();
    const model = process.env.OPENAI_MODEL || "gpt-4o-mini";

    // Build message history for OpenAI
    type OpenAIMessage = {
      role: "system" | "user" | "assistant" | "tool";
      content: string | null;
      tool_calls?: Array<{ id: string; type: "function"; function: { name: string; arguments: string } }>;
      tool_call_id?: string;
      name?: string;
    };

    const openaiMessages: OpenAIMessage[] = [
      { role: "system", content: SYSTEM_PROMPT },
      ...messages.map((m: { role: string; content: string }) => ({
        role: m.role as "user" | "assistant",
        content: m.content,
      })),
    ];

    // ---------------------------------------------------------------------------
    // Agentic function-calling loop (max 5 rounds)
    // ---------------------------------------------------------------------------
    let finalContent = "";
    const MAX_ROUNDS = 5;

    for (let round = 0; round < MAX_ROUNDS; round++) {
      const response = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
        },
        body: JSON.stringify({
          model,
          messages: openaiMessages,
          tools: COACH_TOOLS,
          tool_choice: "auto",
          temperature: 0.7,
        }),
      });

      if (!response.ok) {
        const errText = await response.text();
        throw new Error(`OpenAI API error: ${response.status} - ${errText}`);
      }

      const data = await response.json();
      const choice = data.choices?.[0];

      if (!choice) throw new Error("No choices in OpenAI response");

      const message = choice.message;

      // If the model wants to call tools
      if (choice.finish_reason === "tool_calls" && message.tool_calls?.length) {
        // Append the assistant turn with tool_calls
        openaiMessages.push({
          role: "assistant",
          content: message.content ?? null,
          tool_calls: message.tool_calls,
        });

        // Execute each tool call and append results
        for (const toolCall of message.tool_calls) {
          const toolName = toolCall.function.name as ToolName;
          let toolArgs: Record<string, unknown> = {};
          try {
            toolArgs = JSON.parse(toolCall.function.arguments);
          } catch {
            // ignore parse errors
          }

          let toolResult: unknown;
          try {
            toolResult = await executeTool(convex, effectiveUserId, toolName, toolArgs);
          } catch (err) {
            toolResult = { error: err instanceof Error ? err.message : String(err) };
          }

          openaiMessages.push({
            role: "tool",
            tool_call_id: toolCall.id,
            content: JSON.stringify(toolResult),
          });
        }

        // Continue to next round
        continue;
      }

      // No tool calls — we have the final answer
      finalContent = message.content ?? "";
      break;
    }

    if (!finalContent) {
      finalContent = "I wasn't able to generate a response. Please try again.";
    }

    return NextResponse.json({
      reply: { role: "assistant", content: finalContent },
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
