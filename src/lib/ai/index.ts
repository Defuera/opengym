import { OpenAIClient } from "./providers/openaiClient";
import type { AIPlanner, AIChat, AIMemoryManager } from "./interfaces";
import {
  DefaultAIPlanner,
  DefaultAIChat,
  DefaultAIMemoryManager,
} from "./implementations";

export interface AIConfig {
  provider?: "openai";
  apiKey?: string;
}

export interface AIServices {
  planner: AIPlanner;
  chat: AIChat;
  memoryManager: AIMemoryManager;
}

export function createAI(config: AIConfig = {}): AIServices {
  const provider =
    config.provider ??
    ((process.env.NEXT_PUBLIC_AI_PROVIDER as "openai" | undefined) ??
      "openai");

  if (provider !== "openai") {
    throw new Error(`Unsupported AI provider: ${provider}`);
  }

  const apiKey = config.apiKey ?? process.env.OPENAI_API_KEY;
  if (!apiKey) {
    throw new Error("Missing OPENAI_API_KEY for AI client");
  }

  const client = new OpenAIClient(apiKey);

  return {
    planner: new DefaultAIPlanner(client),
    chat: new DefaultAIChat(client),
    memoryManager: new DefaultAIMemoryManager(client),
  };
}

let cachedAI: AIServices | null = null;

export function getAI(): AIServices {
  if (!cachedAI) {
    cachedAI = createAI();
  }
  return cachedAI;
}

// The AI factory wires provider-specific clients (currently OpenAI) into
// higher-level planner/chat/memory services, so the rest of the app can stay
// provider-agnostic.
