import { randomUUID } from "node:crypto";
import { Hono } from "hono";
import type { AppContext } from "../app-context";
import { kindOf } from "../services/file-text";
import { StructuredImportError } from "../services/structured-import";
import { HttpError, notFound } from "./http";

export const MAX_FILE_BYTES = 20 * 1024 * 1024;

async function readUploads(body: Record<string, unknown>, field: string) {
  const raw = body[field];
  const list = (Array.isArray(raw) ? raw : raw === undefined ? [] : [raw]).filter((x): x is File => typeof x !== "string");
  if (!list.length) throw new HttpError(400, `multipart field "${field}" is required`);
  return Promise.all(
    list.map(async (f) => {
      if (f.size > MAX_FILE_BYTES) throw new HttpError(413, `${f.name} is larger than 20 MB`);
      return { name: f.name || "upload", mime: f.type || "application/octet-stream", bytes: new Uint8Array(await f.arrayBuffer()) };
    }),
  );
}

async function multipart(c: { req: { parseBody(o: { all: true }): Promise<Record<string, unknown>> } }) {
  try {
    return await c.req.parseBody({ all: true });
  } catch {
    throw new HttpError(400, "body must be multipart/form-data");
  }
}

export function fileRoutes({ repos, now }: AppContext) {
  const r = new Hono();

  r.post("/", async (c) => {
    const [up] = await readUploads(await multipart(c), "file");
    const file = repos.files.save({ id: randomUUID(), name: up!.name, mime: up!.mime, size: up!.bytes.length, kind: kindOf(up!.name, up!.mime), createdAt: now() }, up!.bytes);
    return c.json({ file });
  });

  r.get("/:id", (c) => {
    const meta = repos.files.meta(c.req.param("id"));
    const bytes = meta ? repos.files.bytes(meta.id) : null;
    if (!meta || !bytes) throw notFound("file");
    return new Response(Buffer.from(bytes), { headers: { "content-type": meta.mime, "content-length": String(bytes.length) } });
  });
  return r;
}

export function importRoutes({ repos, importRunner }: AppContext) {
  const r = new Hono();

  r.post("/", async (c) => {
    const uploads = await readUploads(await multipart(c), "files");
    return c.json({ job: importRunner.start(uploads) });
  });

  r.post("/structured", async (c) => {
    let raw: unknown;
    try {
      raw = await c.req.json();
    } catch {
      throw new HttpError(400, "body must be JSON");
    }
    try {
      return c.json({ job: importRunner.loadStructured(raw) });
    } catch (e) {
      if (e instanceof StructuredImportError) throw new HttpError(400, e.message);
      throw e;
    }
  });

  r.get("/", (c) => c.json({ jobs: repos.imports.list() }));

  r.get("/:id", (c) => {
    const job = repos.imports.get(c.req.param("id"));
    if (!job) throw notFound("import");
    return c.json({ job });
  });

  r.delete("/:id", (c) => {
    if (!importRunner.remove(c.req.param("id"))) throw notFound("import");
    return c.json({ ok: true });
  });
  return r;
}
