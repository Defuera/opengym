import { internal } from "./_generated/api";
import { Id } from "./_generated/dataModel";

/**
 * Tool classification — read tools execute immediately,
 * write tools queue for user confirmation.
 */

export const READ_TOOLS = new Set([
  "get_sessions",
  "get_session_detail",
  "get_exercise_history",
  "get_exercises",
  "list_memories",
]);

export const WRITE_TOOLS = new Set([
  "create_session",
  "rename_session",
  "delete_session",
  "add_exercise",
  "delete_exercise",
  "log_set",
  "update_set",
  "delete_set",
  "complete_session",
  "save_memory",
  "delete_memory",
]);

type ActionCtx = {
  runQuery: any;
  runMutation: any;
};

export async function executeReadTool(
  ctx: ActionCtx,
  userId: Id<"users">,
  toolName: string,
  args: Record<string, unknown>
): Promise<unknown> {
  switch (toolName) {
    case "get_sessions":
      return ctx.runQuery(internal.aiTools.getSessions, {
        userId,
        status: (args.status as string) ?? undefined,
        limit: (args.limit as number) ?? 10,
      });
    case "get_session_detail":
      return ctx.runQuery(internal.aiTools.getSessionDetail, {
        userId,
        sessionId: args.session_id as Id<"sessions">,
      });
    case "get_exercise_history":
      return ctx.runQuery(internal.aiTools.getExerciseHistory, {
        userId,
        exerciseName: args.exercise_name as string,
        limit: (args.limit as number) ?? 20,
      });
    case "get_exercises":
      return ctx.runQuery(internal.aiTools.getExercises, { userId });
    case "list_memories":
      return ctx.runQuery(internal.aiTools.listMemories, { userId });
    default:
      return { error: `Unknown read tool: ${toolName}` };
  }
}

export async function executeWriteTool(
  ctx: ActionCtx,
  userId: Id<"users">,
  toolName: string,
  args: Record<string, unknown>
): Promise<unknown> {
  switch (toolName) {
    case "create_session":
      return ctx.runMutation(internal.aiTools.createSession, {
        userId,
        name: args.name as string,
      });
    case "rename_session":
      return ctx.runMutation(internal.aiTools.renameSession, {
        userId,
        sessionId: args.session_id as Id<"sessions">,
        name: args.name as string,
      });
    case "delete_session":
      return ctx.runMutation(internal.aiTools.deleteSession, {
        userId,
        sessionId: args.session_id as Id<"sessions">,
      });
    case "add_exercise":
      return ctx.runMutation(internal.aiTools.addExercise, {
        userId,
        sessionId: args.session_id as Id<"sessions">,
        name: args.name as string,
        muscleGroup: args.muscle_group as string,
      });
    case "delete_exercise":
      return ctx.runMutation(internal.aiTools.deleteExercise, {
        userId,
        exerciseId: args.exercise_id as Id<"exercises">,
      });
    case "log_set":
      return ctx.runMutation(internal.aiTools.logSet, {
        userId,
        sessionId: args.session_id as Id<"sessions">,
        exerciseId: args.exercise_id as Id<"exercises">,
        reps: args.reps as number,
        weight: args.weight as number,
      });
    case "update_set":
      return ctx.runMutation(internal.aiTools.updateSet, {
        userId,
        setId: args.set_id as Id<"sets">,
        reps: args.reps as number | undefined,
        weight: args.weight as number | undefined,
      });
    case "delete_set":
      return ctx.runMutation(internal.aiTools.deleteSet, {
        userId,
        setId: args.set_id as Id<"sets">,
      });
    case "complete_session":
      return ctx.runMutation(internal.aiTools.completeSession, {
        userId,
        sessionId: args.session_id as Id<"sessions">,
      });
    case "save_memory":
      return ctx.runMutation(internal.aiTools.saveMemory, {
        userId,
        type: args.type as "preference" | "constraint" | "injury" | "meta",
        key: args.key as string,
        value: args.value as string,
      });
    case "delete_memory":
      return ctx.runMutation(internal.aiTools.deleteMemory, {
        userId,
        memoryId: args.memory_id as Id<"aiMemories">,
      });
    default:
      return { error: `Unknown write tool: ${toolName}` };
  }
}

export function describeWriteAction(
  toolName: string,
  args: Record<string, unknown>
): string {
  switch (toolName) {
    case "create_session":
      return `Create session "${args.name}"`;
    case "rename_session":
      return `Rename session to "${args.name}"`;
    case "delete_session":
      return `Delete session`;
    case "add_exercise":
      return `Add exercise "${args.name}" (${args.muscle_group})`;
    case "delete_exercise":
      return `Delete exercise`;
    case "log_set":
      return `Log set: ${args.reps} reps @ ${args.weight}`;
    case "update_set": {
      const parts = [];
      if (args.reps !== undefined) parts.push(`${args.reps} reps`);
      if (args.weight !== undefined) parts.push(`${args.weight} weight`);
      return `Update set: ${parts.join(", ")}`;
    }
    case "delete_set":
      return `Delete set`;
    case "complete_session":
      return `Complete session`;
    case "save_memory":
      return `Remember: ${args.key} = ${args.value}`;
    case "delete_memory":
      return `Forget memory`;
    default:
      return `${toolName}`;
  }
}
