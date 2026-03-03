/**
 * OpenAI tool definitions for the AI coach.
 * Shared between the coach action and potentially other consumers.
 */

export const COACH_TOOLS = [
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
      description: "Get history of a specific exercise across all sessions — useful for tracking progress.",
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
      parameters: { type: "object", properties: {}, required: [] },
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

export type ToolName =
  | "get_recent_sessions" | "get_session_detail" | "get_exercise_history"
  | "get_exercises" | "create_session" | "log_set" | "complete_session"
  | "add_exercise";

export type OpenAIMessage = {
  role: "system" | "user" | "assistant" | "tool";
  content: string | null;
  tool_calls?: Array<{ id: string; type: "function"; function: { name: string; arguments: string } }>;
  tool_call_id?: string;
};

export const SYSTEM_PROMPT = `You are a personal fitness coach assistant for OpenGym. You have full access to the user's workout data.

When asked about their history, sessions, or exercises — always look it up first using the available tools before answering. Never make up data.

You can also:
- Create new workout sessions
- Log sets with reps and weight
- Add exercises to sessions
- Mark sessions as complete

Be concise, encouraging, and data-driven. Use **markdown** for formatting — bold for key numbers, bullet lists for exercise breakdowns, and headings for structure when helpful.`;
