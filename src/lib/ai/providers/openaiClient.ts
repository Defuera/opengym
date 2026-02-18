"use server";

import { LLMClient, ChatOptions, ChatResult } from "../client";

export class OpenAIClient implements LLMClient {
  private apiKey: string;
  private model: string;

  constructor(apiKey: string) {
    this.apiKey = apiKey;
    this.model = process.env.OPENAI_MODEL || "gpt-4o-mini";
  }

  async chat(options: ChatOptions): Promise<ChatResult> {
    const messages = options.systemPrompt
      ? [{ role: "system" as const, content: options.systemPrompt }, ...options.messages]
      : options.messages;

    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${this.apiKey}`,
      },
      body: JSON.stringify({
        model: this.model,
        messages,
        temperature: 0.7,
      }),
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`OpenAI API error: ${response.status} - ${error}`);
    }

    const data = await response.json();
    const content = data.choices?.[0]?.message?.content;

    if (!content) {
      throw new Error("No content in OpenAI response");
    }

    return { content };
  }
}

export default OpenAIClient;
