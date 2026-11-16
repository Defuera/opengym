import { Doc, Id } from "../../convex/_generated/dataModel";

export type AIMemoryType = "preference" | "constraint" | "injury" | "meta";
export type AIMemorySource = "ai" | "user";

export type AIMemory = Doc<"aiMemories">;

export interface AIMemoryInput {
  userId: Id<"users">;
  type: AIMemoryType;
  key: string;
  value: string;
  source: AIMemorySource;
  expiresAt?: number;
}
