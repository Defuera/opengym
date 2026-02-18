import type {
  SessionPlanInput,
  SessionPlan,
  SessionSummaryInput,
  SessionSummary,
  ChatMessage,
  MemoryChange,
  ChatInput,
  ChatTurn,
  CompressInput,
  CompressedSummary,
} from "./types";

export interface AIPlanner {
  proposeSessionPlan(input: SessionPlanInput): Promise<SessionPlan>;
  adjustSession(
    input: SessionPlanInput & { request: string }
  ): Promise<SessionPlan>;
  summarizeSession(input: SessionSummaryInput): Promise<SessionSummary>;
}

export interface AIMemoryManager {
  extractMemories(input: {
    userId: string;
    messages: ChatMessage[];
  }): Promise<MemoryChange[]>;
}

export interface AIChat {
  reply(input: ChatInput): Promise<ChatTurn>;
  compressHistory(input: CompressInput): Promise<CompressedSummary>;
}
