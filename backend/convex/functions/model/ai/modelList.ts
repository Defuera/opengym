/** Ids that name something other than a text/chat model. */
const NOT_CHAT = /embed|audio|tts|whisper|image|moderation|realtime|dall-e|transcribe/i;

/** Keeps ids that look like text/chat models: strings, no obvious non-chat kind, no duplicates. Sorted. */
export function chatModelIds(ids: unknown[]): string[] {
  const ok = ids.filter((id): id is string => typeof id === "string" && id.length > 0 && id.length <= 100 && !NOT_CHAT.test(id));
  return [...new Set(ok)].sort();
}

/** Tier words, strongest first. The order is an assumption (not read from provider docs); an unknown word goes last. */
const TIERS = ["astra", "sol", "terra", "luna"];
const GPT = /^gpt-(\d+)(?:\.(\d+))?-([a-z]+)$/;

/**
 * The short list the Settings screen shows: every model of the newest generation, plus the newest version of the
 * generation before it. Newest version first, then the stronger tier first. A list with no such ids (another
 * provider) comes back unchanged. Any other id can still be typed under "Other model id".
 */
export function shortModelList(ids: string[]): string[] {
  const rows = ids.flatMap((id) => {
    const m = GPT.exec(id);
    return m ? [{ id, major: Number(m[1]), minor: Number(m[2] ?? 0), tier: TIERS.indexOf(m[3]!) }] : [];
  });
  if (rows.length === 0) return ids;
  const top = Math.max(...rows.map((r) => r.major));
  const prev = rows.filter((r) => r.major === top - 1);
  const prevMinor = Math.max(...prev.map((r) => r.minor));
  const rank = (t: number) => (t < 0 ? TIERS.length : t);
  return rows
    .filter((r) => r.major === top || (r.major === top - 1 && r.minor === prevMinor))
    .sort((a, b) => b.major - a.major || b.minor - a.minor || rank(a.tier) - rank(b.tier) || a.id.localeCompare(b.id))
    .map((r) => r.id);
}
