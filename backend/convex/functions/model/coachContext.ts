import type { ImageInput } from "./ai/provider";
import { contextForPrompt, goalsForPrompt, limitsForPrompt, logForPrompt } from "./ai/jobs/shared";
import { CHUNK_CHARS } from "./fileText";
import { entriesForPrompt } from "./entryContext";
import type { ContextItem, Entry, FileMeta, Goal, Limit, Session } from "./schema";

export interface CoachContext {
  contextBlock: string;
  sources: string[];
  images: ImageInput[];
}

/** One attached file after the action has read it. `image` is set only when the provider takes images. */
export interface AttachedFile {
  meta: Pick<FileMeta, "name" | "kind">;
  text?: string;
  note?: string;
  image?: ImageInput;
}

/** What the coach may read. The caller bounds every list (ADR-012); `sessions` is oldest first. */
export interface CoachData {
  otherThreads: { title: string; summary: string }[];
  sessions: Session[];
  goals: Goal[];
  context: ContextItem[];
  /** Non-cleared limits; no records. Optional so old callers keep working. */
  limits?: Limit[];
  /** Log entries of the last week, oldest first. Optional so old callers keep working. */
  entries?: Entry[];
}

/** Port of services/coach-context.ts. Pure. Records what the coach actually read in `sources`. */
export function assembleCoachContext(data: CoachData, files: AttachedFile[], supportsImages: boolean, entryImages: ImageInput[] = []): CoachContext {
  const sources: string[] = [];
  const parts: string[] = [];
  const images: ImageInput[] = [];

  const others = data.otherThreads.filter((t) => t.summary.trim()).slice(0, 8);
  if (others.length) {
    parts.push(`Other threads (summaries):\n${others.map((t) => `- ${t.title}: ${t.summary}`).join("\n")}`);
    for (const t of others) sources.push(`${t.title} thread`);
  }
  if (data.sessions.length) {
    parts.push(`Recent log (oldest first):\n${JSON.stringify(logForPrompt(data.sessions, 10))}`);
    sources.push("gym log");
  }
  const goals = data.goals.filter((g) => g.status === "active");
  if (goals.length) {
    parts.push(`Active goals:\n${JSON.stringify(goalsForPrompt(goals))}`);
    sources.push("goals");
  }
  const ctx = contextForPrompt(data.context);
  if (ctx.length) {
    parts.push(`Active context notes from the user:\n${JSON.stringify(ctx)}`);
    sources.push("context notes");
  }
  const limits = limitsForPrompt(data.limits ?? []);
  if (limits.length) {
    parts.push(`Limits the user trains around:\n${JSON.stringify(limits)}`);
    sources.push("limits");
  }
  if (data.entries?.length) {
    parts.push(`Log entries from the user, free notes (oldest first):\n${JSON.stringify(entriesForPrompt(data.entries))}`);
    sources.push("log entries");
  }
  if (supportsImages && entryImages.length) {
    images.push(...entryImages);
    parts.push("Photos from the user's log entries of the last day are shown to you (newest first).");
  }

  for (const f of files) {
    if (f.meta.kind === "image") {
      if (supportsImages && f.image) {
        images.push(f.image);
        parts.push(`Attached image: ${f.meta.name} (shown to you).`);
        sources.push(`file: ${f.meta.name}`);
      } else {
        parts.push(`Attached image: ${f.meta.name} (this AI provider cannot read images; tell the user so).`);
      }
      continue;
    }
    if (f.text) {
      const clipped = f.text.length > CHUNK_CHARS;
      parts.push(`Attached file ${f.meta.name}${clipped ? ` (first ${CHUNK_CHARS} characters)` : ""}:\n${f.text.slice(0, CHUNK_CHARS)}`);
      sources.push(`file: ${f.meta.name}`);
    } else if (f.note) {
      parts.push(`Attached file note: ${f.note}`);
    }
  }
  return { contextBlock: parts.join("\n\n") || "(no other data yet)", sources, images };
}
