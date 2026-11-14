import { logForPrompt, goalsForPrompt, contextForPrompt } from "../ai/jobs/shared";
import type { ImageInput } from "../ai/provider";
import type { Repositories } from "../repositories/types";
import { CHUNK_CHARS, extractText, imageMime } from "./file-text";

export interface CoachContext {
  contextBlock: string;
  sources: string[];
  images: ImageInput[];
}

/** Gathers what the coach may read and records what it actually read in `sources`. */
export async function assembleCoachContext(
  repos: Repositories,
  threadId: string,
  fileIds: string[],
  supportsImages: boolean,
): Promise<CoachContext> {
  const sources: string[] = [];
  const parts: string[] = [];
  const images: ImageInput[] = [];

  const others = repos.threads.list().filter((t) => t.id !== threadId && t.summary.trim());
  if (others.length) {
    parts.push(`Other threads (summaries):\n${others.slice(0, 8).map((t) => `- ${t.title}: ${t.summary}`).join("\n")}`);
    for (const t of others.slice(0, 8)) sources.push(`${t.title} thread`);
  }

  const sessions = repos.sessions.list();
  if (sessions.length) {
    parts.push(`Recent log (oldest first):\n${JSON.stringify(logForPrompt(sessions, 10))}`);
    sources.push("gym log");
  }
  const goals = repos.goals.list().filter((g) => g.status === "active");
  if (goals.length) {
    parts.push(`Active goals:\n${JSON.stringify(goalsForPrompt(goals))}`);
    sources.push("goals");
  }
  const ctx = contextForPrompt(repos.context.list());
  if (ctx.length) {
    parts.push(`Active context notes from the user:\n${JSON.stringify(ctx)}`);
    sources.push("context notes");
  }

  for (const id of fileIds) {
    const meta = repos.files.meta(id);
    const bytes = meta ? repos.files.bytes(id) : null;
    if (!meta || !bytes) continue;
    if (meta.kind === "image") {
      if (supportsImages) {
        images.push({ mime: imageMime(meta), base64: Buffer.from(bytes).toString("base64") });
        parts.push(`Attached image: ${meta.name} (shown to you).`);
        sources.push(`file: ${meta.name}`);
      } else {
        parts.push(`Attached image: ${meta.name} (this AI provider cannot read images; tell the user so).`);
      }
      continue;
    }
    const ex = await extractText(meta, bytes);
    if (ex.text) {
      const clipped = ex.text.length > CHUNK_CHARS;
      parts.push(`Attached file ${meta.name}${clipped ? ` (first ${CHUNK_CHARS} characters)` : ""}:\n${ex.text.slice(0, CHUNK_CHARS)}`);
      sources.push(`file: ${meta.name}`);
    } else if (ex.note) {
      parts.push(`Attached file note: ${ex.note}`);
    }
  }

  return { contextBlock: parts.join("\n\n") || "(no other data yet)", sources, images };
}
