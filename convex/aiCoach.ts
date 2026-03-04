import { v } from "convex/values";
import { action } from "./_generated/server";
import { api, internal } from "./_generated/api";
import { Id } from "./_generated/dataModel";
import { COACH_TOOLS, buildSystemPrompt, type ToolName, type OpenAIMessage } from "./aiCoachDefs";
import { READ_TOOLS, WRITE_TOOLS, executeReadTool, describeWriteAction } from "./aiCoachTools";

const MAX_ROUNDS = 5;

export const chat = action({
  args: {
    threadId: v.id("aiThreads"),
    userMessage: v.string(),
  },
  handler: async (ctx, args): Promise<{ threadId: Id<"aiThreads">; messageId: Id<"aiMessages"> }> => {
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) throw new Error("OPENAI_API_KEY not configured");

    const userId: Id<"users"> = await ctx.runMutation(
      api.users.getOrCreateDefaultUser,
      {}
    );
    const model = process.env.OPENAI_MODEL || "gpt-5.2";

    // Save user message to DB
    await ctx.runMutation(internal.aiMessages.saveMessage, {
      threadId: args.threadId,
      role: "user" as const,
      content: args.userMessage,
    });

    // Load thread history and user context in parallel
    const [dbMessages, userContext] = await Promise.all([
      ctx.runQuery(api.aiMessages.listMessages, {
        threadId: args.threadId,
      }),
      ctx.runQuery(internal.aiCoachContext.buildCoachContext, { userId }),
    ]);

    // Build system prompt with injected user context
    const systemContent = userContext
      ? `${buildSystemPrompt()}\n\n---\n${userContext}`
      : buildSystemPrompt();

    // Build OpenAI messages from DB history (cap at last 30)
    const recentMessages = dbMessages.slice(-30);
    const openaiMessages: OpenAIMessage[] = [
      { role: "system", content: systemContent },
      ...recentMessages.map((m: { role: string; content: string }) => ({
        role: m.role as "user" | "assistant",
        content: m.content,
      })),
    ];

    let finalContent = "";
    const pendingWriteCalls: Array<{
      toolCallId: string;
      toolName: string;
      toolArgs: Record<string, unknown>;
    }> = [];

    for (let round = 0; round < MAX_ROUNDS; round++) {
      const response = await fetch(
        "https://api.openai.com/v1/chat/completions",
        {
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
        }
      );

      if (!response.ok) {
        const errText = await response.text();
        throw new Error(`OpenAI API error: ${response.status} - ${errText}`);
      }

      const data = await response.json();
      const choice = data.choices?.[0];
      if (!choice) throw new Error("No choices in OpenAI response");

      const message = choice.message;

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
              content: JSON.stringify({
                error: "Failed to parse tool arguments",
              }),
            });
            continue;
          }

          if (READ_TOOLS.has(toolName)) {
            let toolResult: unknown;
            try {
              toolResult = await executeReadTool(
                ctx as any,
                userId,
                toolName,
                toolArgs
              );
            } catch (err) {
              toolResult = {
                error: err instanceof Error ? err.message : String(err),
              };
            }

            openaiMessages.push({
              role: "tool",
              tool_call_id: toolCall.id,
              content: JSON.stringify(toolResult),
            });
          } else if (WRITE_TOOLS.has(toolName)) {
            // Queue write tool for user confirmation
            pendingWriteCalls.push({
              toolCallId: toolCall.id,
              toolName,
              toolArgs,
            });

            openaiMessages.push({
              role: "tool",
              tool_call_id: toolCall.id,
              content: JSON.stringify({
                status: "pending_confirmation",
                message:
                  "This action requires user confirmation before executing.",
              }),
            });
          } else {
            openaiMessages.push({
              role: "tool",
              tool_call_id: toolCall.id,
              content: JSON.stringify({ error: `Unknown tool: ${toolName}` }),
            });
          }
        }
        continue;
      }

      finalContent = message.content ?? "";
      break;
    }

    if (!finalContent) {
      finalContent = "I wasn't able to generate a response. Please try again.";
    }

    // Build toolCalls array for the assistant message
    const toolCallsForDb =
      pendingWriteCalls.length > 0
        ? pendingWriteCalls.map((tc) => ({
            id: tc.toolCallId,
            name: tc.toolName,
            arguments: JSON.stringify(tc.toolArgs),
          }))
        : undefined;

    // Save assistant message to DB
    const messageId: Id<"aiMessages"> = await ctx.runMutation(
      internal.aiMessages.saveMessage,
      {
        threadId: args.threadId,
        role: "assistant" as const,
        content: finalContent,
        toolCalls: toolCallsForDb,
        model,
      }
    );

    // Create aiActions rows for write tool calls
    for (const tc of pendingWriteCalls) {
      await ctx.runMutation(internal.aiActions_internal.createAction, {
        messageId,
        threadId: args.threadId,
        toolCallId: tc.toolCallId,
        toolName: tc.toolName,
        toolArgs: JSON.stringify(tc.toolArgs),
        description: describeWriteAction(tc.toolName, tc.toolArgs),
      });
    }

    return { threadId: args.threadId, messageId };
  },
});
