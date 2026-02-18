import type { AIMemory } from "@/types/aiMemory";

export interface SessionPlanInput {
  userId: string;
  goal: "strength" | "hypertrophy" | "fat_loss" | "general" | "rehab";
  currentSessionId?: string | null;
  recentSessions: any[];
  memories: AIMemory[];
}

export interface SessionExerciseSet {
  exerciseId: string;
  sets: {
    targetReps: number;
    targetWeight?: number;
    targetRpe?: number;
    notes?: string;
  }[];
}

export interface SessionPlan {
  title: string;
  description?: string;
  exercises: SessionExerciseSet[];
  rationale?: string;
}

export interface SessionSummaryInput {
  userId: string;
  sessionId: string;
  sessionData: any;
  memories: AIMemory[];
}

export interface SessionSummary {
  headline: string;
  positives: string[];
  risks: string[];
  advice: string[];
}

export interface ChatMessage {
  id?: string;
  role: "user" | "assistant" | "system";
  content: string;
  createdAt?: number;
  sessionId?: string | null;
}

export interface ChatInput {
  userId: string;
  messages: ChatMessage[];
  sessionId?: string | null;
}

export interface ChatTurn {
  reply: ChatMessage;
  memoryChanges?: MemoryChange[];
}

export interface CompressInput {
  userId: string;
  chatId: string;
  messages: ChatMessage[];
}

export interface CompressedSummary {
  summary: string;
}

export type MemoryChangeAction = "create" | "update" | "archive";

export interface MemoryChange {
  action: MemoryChangeAction;
  targetId?: string;
  data?: Partial<AIMemory>;
}
