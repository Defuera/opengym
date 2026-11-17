import type { HttpProviderOptions } from "../provider";
import { OpenAiCompatibleProvider } from "./openaiCompatible";

export const createDeepSeekProvider = (o: HttpProviderOptions) =>
  new OpenAiCompatibleProvider({
    ...o,
    name: "deepseek",
    defaultBaseUrl: "https://api.deepseek.com",
    path: "/chat/completions",
    supportsImages: false,
    maxTokensField: "max_tokens",
  });
