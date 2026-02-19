"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.OpenAIClient = void 0;
// This client is only used from server-side code (API routes, Convex helpers).
// We deliberately do NOT mark this file with "use server" because Next.js
// requires only async exports in such files, and this class is a sync export.
class OpenAIClient {
    constructor(apiKey) {
        this.apiKey = apiKey;
        // TEMP: hardcode model while Vercel env access is blocked.
        // To revert, change back to: process.env.OPENAI_MODEL || "gpt-4o-mini".
        this.model = "gpt-5.2";
    }
    async chat(options) {
        const messages = options.systemPrompt
            ? [{ role: "system", content: options.systemPrompt }, ...options.messages]
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
exports.OpenAIClient = OpenAIClient;
