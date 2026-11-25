import { ConvexError, v } from "convex/values";
import { internal } from "../_generated/api";
import { action } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { transcribeFile } from "../lib/transcribe";
import { MAX_VOICE_BYTES } from "../model/voice";

/**
 * The text of a recording, for the app to show in the text field before the person sends it (ADR-034).
 * The audio is already uploaded (commands/files:register, kind "audio"). Nothing is stored as a message and the coach does not run.
 * Success: `{ ok: true, text }` (trimmed, at most 8000 characters) and the audio file is removed (blob and row), as no message holds it.
 * Failure: `{ ok: false, reason }` with a short reduced text, never a provider message; the file stays, so the app can try again.
 * An unknown token throws "unauthorized"; a file that is not audio or is over 10 MB throws a ConvexError.
 */
export const transcribe = action({
  args: { token: v.string(), fileId: v.string() },
  handler: async (ctx, { token, fileId }): Promise<{ ok: true; text: string } | { ok: false; reason: string }> => {
    requireToken(token);
    const file = await ctx.runQuery(internal.jobs.voice.audioFile, { fileId });
    if (!file) return { ok: false, reason: "The recording is gone." };
    if (file.size > MAX_VOICE_BYTES) throw new ConvexError("fileId: the recording is larger than 10 MB");
    const out = await transcribeFile(ctx, file);
    if (!out.ok) {
      console.error(`[voice] transcription failed: ${out.why}`);
      return { ok: false, reason: out.why };
    }
    await ctx.runMutation(internal.jobs.voice.dropAudio, { fileId });
    return { ok: true, text: out.text };
  },
});
