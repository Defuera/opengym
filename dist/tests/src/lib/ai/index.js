"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createAI = createAI;
exports.getAI = getAI;
const openaiClient_1 = require("./providers/openaiClient");
const implementations_1 = require("./implementations");
function createAI(config = {}) {
    const provider = config.provider ??
        (process.env.NEXT_PUBLIC_AI_PROVIDER ??
            "openai");
    if (provider !== "openai") {
        throw new Error(`Unsupported AI provider: ${provider}`);
    }
    const apiKey = config.apiKey ?? process.env.OPENAI_API_KEY;
    if (!apiKey) {
        throw new Error("Missing OPENAI_API_KEY for AI client");
    }
    const client = new openaiClient_1.OpenAIClient(apiKey);
    return {
        planner: new implementations_1.DefaultAIPlanner(client),
        chat: new implementations_1.DefaultAIChat(client),
        memoryManager: new implementations_1.DefaultAIMemoryManager(client),
    };
}
let cachedAI = null;
function getAI() {
    if (!cachedAI) {
        cachedAI = createAI();
    }
    return cachedAI;
}
// The AI factory wires provider-specific clients (currently OpenAI) into
// higher-level planner/chat/memory services, so the rest of the app can stay
// provider-agnostic.
