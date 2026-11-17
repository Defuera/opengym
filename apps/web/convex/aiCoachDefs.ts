/**
 * OpenAI tool definitions for the AI coach.
 * Shared between the coach action and potentially other consumers.
 */

export const COACH_TOOLS = [
  // --- READ TOOLS ---
  {
    type: "function" as const,
    function: {
      name: "get_sessions",
      description:
        "Get the user's workout sessions with exercise names. Always call this before answering questions about workout history.",
      parameters: {
        type: "object",
        properties: {
          status: {
            type: "string",
            enum: ["planned", "active", "completed"],
            description: "Filter by session status (omit for all)",
          },
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
      name: "list_memories",
      description: "List everything you remember about the user (preferences, injuries, constraints).",
      parameters: { type: "object", properties: {}, required: [] },
    },
  },
  // --- WRITE TOOLS ---
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
      name: "rename_session",
      description: "Rename an existing workout session.",
      parameters: {
        type: "object",
        properties: {
          session_id: { type: "string", description: "The session ID" },
          name: { type: "string", description: "New name for the session" },
        },
        required: ["session_id", "name"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "delete_session",
      description: "Delete a workout session and all its exercises and sets. This is irreversible.",
      parameters: {
        type: "object",
        properties: {
          session_id: { type: "string", description: "The session ID to delete" },
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
  {
    type: "function" as const,
    function: {
      name: "delete_exercise",
      description: "Delete an exercise and all its sets from a session.",
      parameters: {
        type: "object",
        properties: {
          exercise_id: { type: "string", description: "The exercise ID to delete" },
        },
        required: ["exercise_id"],
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
      name: "update_set",
      description: "Update the reps and/or weight of an existing set.",
      parameters: {
        type: "object",
        properties: {
          set_id: { type: "string", description: "The set ID to update" },
          reps: { type: "number", description: "New number of reps" },
          weight: { type: "number", description: "New weight" },
        },
        required: ["set_id"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "delete_set",
      description: "Delete a specific set from an exercise.",
      parameters: {
        type: "object",
        properties: {
          set_id: { type: "string", description: "The set ID to delete" },
        },
        required: ["set_id"],
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
      name: "save_memory",
      description:
        "Save a fact about the user for future reference (preference, injury, constraint, or meta). Upserts by key.",
      parameters: {
        type: "object",
        properties: {
          type: {
            type: "string",
            enum: ["preference", "constraint", "injury", "meta"],
            description: "Category of the memory",
          },
          key: { type: "string", description: "Short identifier, e.g. 'bad_knee', 'preferred_split'" },
          value: { type: "string", description: "The detail to remember" },
        },
        required: ["type", "key", "value"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "delete_memory",
      description: "Delete a previously saved memory about the user.",
      parameters: {
        type: "object",
        properties: {
          memory_id: { type: "string", description: "The memory ID to delete" },
        },
        required: ["memory_id"],
      },
    },
  },
] as const;

export type ToolName =
  | "get_sessions" | "get_session_detail" | "get_exercise_history"
  | "get_exercises" | "list_memories"
  | "create_session" | "rename_session" | "delete_session"
  | "add_exercise" | "delete_exercise"
  | "log_set" | "update_set" | "delete_set"
  | "complete_session"
  | "save_memory" | "delete_memory";

export type OpenAIMessage = {
  role: "system" | "user" | "assistant" | "tool";
  content: string | null;
  tool_calls?: Array<{ id: string; type: "function"; function: { name: string; arguments: string } }>;
  tool_call_id?: string;
};

export function buildSystemPrompt(): string {
  const today = new Date().toLocaleDateString("en-US", {
    weekday: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
  });

  return `You are a personal fitness coach assistant for OpenGym. You have full access to the user's workout data.

Today is ${today}.

When asked about their history, sessions, or exercises — always look it up first using the available tools before answering. Never make up data.

You can:
- **Read** sessions (with status/limit filters), session detail, exercise history, exercise catalog, and your memories about the user
- **Create** sessions, add exercises, log sets
- **Update** session names, set reps/weight
- **Delete** sessions, exercises, sets, and memories
- **Remember** facts about the user (injuries, preferences, constraints) using save_memory

**Important:** Write actions (creating, updating, deleting) require user confirmation before they execute. When you call a write tool, the user will see a confirmation card and must approve it. Mention this naturally — e.g. "I'll create that session for you — please confirm below."

Be concise, encouraging, and data-driven. Use **markdown** for formatting — bold for key numbers, bullet lists for exercise breakdowns, and headings for structure when helpful.`;
}
