import { randomUUID } from "node:crypto";
import { importDataJob } from "../ai/jobs";
import { IMPORT_NEEDS_AI_NOTE } from "../ai/jobs/import-data";
import type { ImportInput } from "../ai/jobs/import-data";
import type { AiRunner } from "../ai/run-job";
import type { Repositories } from "../repositories/types";
import { type FileMeta, type ImportJob, type ImportSessionDraft, type Session, SessionSchema } from "../schema";
import { CHUNK_CHARS, MAX_CHUNKS, chunkText, extractText, imageMime, kindOf } from "./file-text";
import type { TaskQueue } from "./queue";
import type { Refresher } from "./refresh";
import { parseStructuredImport } from "./structured-import";

export interface UploadedFile {
  name: string;
  mime: string;
  bytes: Uint8Array;
}

interface Unit {
  file: FileMeta;
  input: ImportInput;
}

export function createImportRunner(deps: { repos: Repositories; ai: AiRunner; queue: TaskQueue; refresher: Refresher; now: () => number }) {
  const { repos, ai, queue, refresher, now } = deps;

  async function buildUnits(files: FileMeta[], notes: Set<string>): Promise<Unit[]> {
    const uploadedAt = new Date(now()).toISOString();
    const units: Unit[] = [];
    for (const meta of files) {
      const bytes = repos.files.bytes(meta.id);
      if (!bytes) continue;
      if (meta.kind === "image") {
        if (ai.provider && !ai.provider.supportsImages) {
          notes.add(`${meta.name}: ${ai.provider.name} has no image input, so this photo was skipped.`);
          continue;
        }
        units.push({ file: meta, input: { fileName: meta.name, uploadedAt, chunkIndex: 0, chunkCount: 1, image: { mime: imageMime(meta), base64: Buffer.from(bytes).toString("base64") } } });
        continue;
      }
      const ex = await extractText(meta, bytes);
      if (ex.note) notes.add(ex.note);
      if (!ex.text) continue;
      const { chunks, total } = chunkText(ex.text);
      if (total > chunks.length) notes.add(`${meta.name}: only the first ${MAX_CHUNKS} of ${total} chunks (${CHUNK_CHARS} chars each) were processed.`);
      chunks.forEach((chunk, i) => units.push({ file: meta, input: { fileName: meta.name, uploadedAt, chunk, chunkIndex: i, chunkCount: chunks.length } }));
    }
    return units;
  }

  function toSession(d: ImportSessionDraft, file: FileMeta, jobId: string, notes: Set<string>): Session | null {
    let at = d.date ? Date.parse(d.date) : NaN;
    if (Number.isNaN(at)) {
      at = file.createdAt;
      notes.add(`${file.name}: no date found for some sessions, used the file's upload time (${new Date(file.createdAt).toISOString()}).`);
    }
    const parsed = SessionSchema.safeParse({
      id: randomUUID(),
      kind: d.kind,
      type: d.type,
      startedAt: at - (d.minutes ?? 0) * 60_000,
      endedAt: at,
      exercises: d.kind === "gym" ? d.exercises : [],
      minutes: d.minutes,
      distanceKm: d.distanceKm,
      note: d.note,
      source: "import",
      importId: jobId,
    });
    if (!parsed.success) {
      notes.add(`${file.name}: skipped a session that did not validate (${parsed.error.issues[0]?.message}).`);
      return null;
    }
    return parsed.data;
  }

  async function run(job: ImportJob, files: FileMeta[]) {
    const notes = new Set<string>();
    const save = (patch: Partial<ImportJob>) => {
      if (!repos.imports.get(job.id)) return false; // deleted while running
      job = { ...job, ...patch, notes: [...notes] };
      repos.imports.put(job);
      return true;
    };
    try {
      const units = await buildUnits(files, notes);
      if (!save({ total: units.length })) return;
      for (const u of units) {
        const r = await ai.run(importDataJob, u.input);
        const counts = { ...job.counts };
        for (const n of r.value.notes) notes.add(`${u.file.name}: ${n}`);
        for (const d of r.value.sessions) {
          const s = toSession(d, u.file, job.id, notes);
          if (s) {
            repos.sessions.upsert(s);
            counts.sessions++;
          }
        }
        for (const g of r.value.goals) {
          repos.goals.put({ ...g, id: randomUUID(), status: "active", source: "import", importId: job.id, createdAt: now() });
          counts.goals++;
        }
        for (const c of r.value.context) {
          repos.context.put({ id: randomUUID(), text: c.text, topic: c.topic, active: true, source: "import", importId: job.id, createdAt: now() });
          counts.context++;
        }
        if (!save({ processed: job.processed + 1, counts })) return;
      }
      if (save({ status: "done" })) refresher.factsChanged();
    } catch (e) {
      notes.add(`Import failed: ${(e as Error).message}`);
      save({ status: "failed" });
    }
  }

  return {
    /** Stores the files, creates the job and returns at once; processing runs in the background queue. */
    start(uploads: UploadedFile[]): ImportJob {
      const metas = uploads.map((u): FileMeta => repos.files.save({ id: randomUUID(), name: u.name, mime: u.mime || "application/octet-stream", size: u.bytes.length, kind: kindOf(u.name, u.mime), createdAt: now() }, u.bytes));
      const job: ImportJob = { id: randomUUID(), status: "running", total: metas.length, processed: 0, counts: { sessions: 0, goals: 0, context: 0 }, notes: [], createdAt: now() };
      repos.imports.put(job);
      queue.enqueue(`import:${job.id}`, () => run(job, metas));
      return job;
    },
    /** Loads ready sessions, goals and context as one finished import. No AI call, no per-session review. Throws StructuredImportError. */
    loadStructured(raw: unknown): ImportJob {
      const id = randomUUID();
      const { sessions, goals, context, note } = parseStructuredImport(raw, id);
      const total = sessions.length + goals.length + context.length;
      const job: ImportJob = { id, status: "done", total, processed: total, counts: { sessions: sessions.length, goals: goals.length, context: context.length }, notes: note ? [note] : [], createdAt: now() };
      repos.imports.put(job);
      for (const s of sessions) repos.sessions.upsert(s);
      for (const g of goals) repos.goals.put({ ...g, id: randomUUID(), status: "active", source: "import", importId: id, createdAt: now() });
      for (const c of context) repos.context.put({ id: randomUUID(), text: c.text, topic: c.topic, active: true, source: "import", importId: id, createdAt: now() });
      refresher.factsChanged();
      return job;
    },
    /** Removes every item created by the import, and the job itself. Null if unknown. */
    remove(id: string): boolean {
      if (!repos.imports.get(id)) return false;
      repos.sessions.deleteByImport(id);
      repos.goals.deleteByImport(id);
      repos.context.deleteByImport(id);
      repos.imports.delete(id);
      refresher.factsChanged();
      return true;
    },
  };
}

export type ImportRunner = ReturnType<typeof createImportRunner>;
export { IMPORT_NEEDS_AI_NOTE };
