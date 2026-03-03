import { v } from "convex/values";
import { action } from "./_generated/server";
import { internal } from "./_generated/api";
import { Id } from "./_generated/dataModel";
import { COACH_TOOLS, SYSTEM_PROMPT, type ToolName, type OpenAIMessage } from "./aiCoachDefs";

const MAX_ROUNDS = 5;

async function executeTool(
  ctx: { runQuery: typeof action.prototype; runMutation: typeof action.prototype },
  userId: Id<"users">,
  toolName: ToolName,
  args: Record<string, unknown>
): Promise<unknown> {
  switch (toolName) {
    case "get_recent_sessions":
      return (ctx as any).runQuery(internal.aiTools.getRecentSessions, {
        userId,
        limit: (args.limit as number) ?? 10,
      });
    case "get_session_detail":
      return (ctx as any).runQuery(internal.aiTools.getSessionDetail, {
        userId,
        sessionId: args.session_id as Id<"sessions">,
      });
    case "get_exercise_history":
      return (ctx as any).runQuery(internal.aiTools.getExerciseHistory, {
        userId,
        exerciseName: args.exercise_name as string,
        limit: (args.limit as number) ?? 20,
      });
    case "get_exercises":
      return (ctx as any).runQuery(internal.aiTools.getExercises, { userId });
    case "create_session":
      return (ctx as any).runMutation(internal.aiTools.createSession, {
        userId,
        name: args.name as string,
      });
    case "log_set":
      return (ctx as any).runMutation(internal.aiTools.logSet, {
        userId,
        sessionId: args.session_id as Id<"sessions">,
        exerciseId: args.exercise_id as Id<"exercises">,
        reps: args.reps as number,
        weight: args.weight as number,
      });
    case "complete_session":
      return (ctx as any).runMutation(internal.aiTools.completeSession, {
        userId,
        sessionId: args.session_id as Id<"sessions">,
      });
    case "add_exercise":
      return (ctx as any).runMutation(internal.aiTools.addExercise, {
        userId,
        sessionId: args.session_id as Id<"sessions">,
        name: args.name as string,
        muscleGroup: args.muscle_group as string,
      });
    default:
      return { error: `Unknown tool: ${toolName}` };
  }
}

export const chat = action({
  args: {
    messages: v.array(v.object({
      role: v.string(),
      content: v.string(),
    })),
  },
  handler: async (ctx, args) => {
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) throw new Error("OPENAI_API_KEY not configured");

    // Hardcoded until auth is added
    const userId = "default-user" as Id<"users">;
    const model = process.env.OPENAI_MODEL || "gpt-4o-mini";

    // Sanitize message roles — only allow user/assistant from client input
    const sanitizedMessages: OpenAIMessage[] = args.messages
      .filter((m) => m.role === "user" || m.role === "assistant")
      .map((m) => ({
        role: m.role as "user" | "assistant",
        content: m.content,
      }));

    const openaiMessages: OpenAIMessage[] = [
      { role: "system", content: SYSTEM_PROMPT },
      ...sanitizedMessages,
    ];

    let finalContent = "";

    for (let round = 0; round < MAX_ROUNDS; round++) {
      const response = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${apiKey}`,
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

      // Check for tool calls — use message.tool_calls presence (more reliable than finish_reason)
      if (message.tool_calls?.length) {
        openaiMessages.push({
          role: "assistant",
          content: message.content ?? null,
          tool_calls: message.tool_calls,
        });

        for (const toolCall of message.tool_calls) {
          const toolName = toolCall.function.name as ToolName;
          let toolArgs: Record<string, unknown> = {};
          try {
            toolArgs = JSON.parse(toolCall.function.arguments);
          } catch {
            openaiMessages.push({
              role: "tool",
              tool_call_id: toolCall.id,
              content: JSON.stringify({ error: "Failed to parse tool arguments" }),
            });
            continue;
          }

          let toolResult: unknown;
          try {
            toolResult = await executeTool(ctx as any, userId, toolName, toolArgs);
          } catch (err) {
            toolResult = { error: err instanceof Error ? err.message : String(err) };
          }

          openaiMessages.push({
            role: "tool",
            tool_call_id: toolCall.id,
            content: JSON.stringify(toolResult),
          });
        }
        continue;
      }

      finalContent = message.content ?? "";
      break;
    }

    if (!finalContent) {
      finalContent = "I wasn't able to generate a response. Please try again.";
    }

    return finalContent;
  },
});
