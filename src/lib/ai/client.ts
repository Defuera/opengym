export interface ChatOptions {
  systemPrompt?: string;
  messages: {
    role: "system" | "user" | "assistant";
    content: string;
  }[];
}

export interface ChatResult {
  content: string;
}

export interface LLMClient {
  chat(options: ChatOptions): Promise<ChatResult>;
}
