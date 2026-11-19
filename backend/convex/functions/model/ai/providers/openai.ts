import type { HttpProviderOptions } from "../provider";
import { OpenAiCompatibleProvider } from "./openaiCompatible";

export const createOpenAiProvider = (o: HttpProviderOptions) =>
  new OpenAiCompatibleProvider({
    ...o,
    name: "openai",
    defaultBaseUrl: "https://api.openai.com",
    path: "/v1/chat/completions",
    modelsPath: "/v1/models",
    transcribePath: "/v1/audio/transcriptions",
    imagePath: "/v1/images",
    supportsImages: true,
    maxTokensField: "max_completion_tokens",
  });
