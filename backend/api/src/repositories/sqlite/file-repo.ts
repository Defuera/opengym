import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import type { Database } from "better-sqlite3";
import type { FileMeta } from "../../schema";
import type { FileRepository } from "../types";
import { DocStore } from "./doc-store";

export class SqliteFileRepository implements FileRepository {
  private readonly store: DocStore<FileMeta>;

  constructor(
    db: Database,
    private readonly dir: string,
  ) {
    mkdirSync(dir, { recursive: true });
    this.store = new DocStore<FileMeta>(db, "files");
  }

  private pathFor(id: string) {
    return path.join(this.dir, path.basename(id));
  }

  save(meta: FileMeta, bytes: Uint8Array) {
    writeFileSync(this.pathFor(meta.id), bytes);
    return this.store.put(meta);
  }
  meta(id: string) {
    return this.store.get(id);
  }
  bytes(id: string) {
    if (!this.store.get(id)) return null;
    const p = this.pathFor(id);
    return existsSync(p) ? new Uint8Array(readFileSync(p)) : null;
  }
  remove(id: string) {
    rmSync(this.pathFor(id), { force: true });
    this.store.delete(id);
  }
}
