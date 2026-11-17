/** Ids that name something other than a text/chat model. */
const NOT_CHAT = /embed|audio|tts|whisper|image|moderation|realtime|dall-e|transcribe/i;

/** Keeps ids that look like text/chat models: strings, no obvious non-chat kind, no duplicates. Sorted. */
export function chatModelIds(ids: unknown[]): string[] {
  const ok = ids.filter((id): id is string => typeof id === "string" && id.length > 0 && id.length <= 100 && !NOT_CHAT.test(id));
  return [...new Set(ok)].sort();
}
