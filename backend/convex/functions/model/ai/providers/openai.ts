import type { HttpProviderOptions } from "../provider";
import { OpenAiCompatibleProvider } from "./openaiCompatible";

export const createOpenAiProvider = (o: HttpProviderOptions) =>
  new OpenAiCompatibleProvider({
    ...o,
    name: "openai",
    defaultBaseUrl: "https://api.openai.com",
    path: "/v1/chat/completions",
    supportsImages: true,
    maxTokensField: "max_completion_tokens",
  });
