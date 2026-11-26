import type { ActionCtx } from "../_generated/server";
import { listError } from "../jobs/models";
import { MESSAGE_MAX_CHARS } from "../model/schema";
import { providerFor } from "./ai";
import { countedCall } from "./countedCall";
import { type FileDoc, fileBytes } from "./files";

/** The result of one speech-to-text run. `why` is a short reduced text, never a provider message. */
export type Transcript = { ok: true; text: string } | { ok: false; why: string };

/**
 * Speech to text for one stored audio file. Shared by the voice message job (jobs/voice:transcribe) and the public
 * action commands/voice:transcribe. The text is trimmed and capped like a typed message. Never throws.
 */
export async function transcribeFile(ctx: ActionCtx, userId: string, file: FileDoc | null): Promise<Transcript> {
  try {
    const provider = await providerFor(ctx, userId);
    if (!provider?.transcribe) return { ok: false, why: "The AI provider cannot transcribe." };
    const bytes = file ? await fileBytes(ctx, file) : null;
    if (!file || !bytes) return { ok: false, why: "The recording is gone." };
    const meta = { userId, job: "transcribe", kind: "transcribe" as const, provider: provider.name, model: provider.transcribeModel ?? "unknown", ref: file.fileId, audioBytes: bytes.length };
    const text = (await countedCall(ctx, meta, (onUsage) => provider.transcribe!(bytes, file.mime, file.name, { onUsage }))).trim().slice(0, MESSAGE_MAX_CHARS);
    return text ? { ok: true, text } : { ok: false, why: "No speech was heard." };
  } catch (e) {
    return { ok: false, why: listError(e) };
  }
}
