import type { Database } from "better-sqlite3";

export interface Column<T> {
  type: "INTEGER" | "TEXT";
  get: (doc: T) => string | number | null | undefined;
}

/** A table of JSON documents with a few indexed columns. */
export class DocStore<T extends { id: string }> {
  private readonly cols: string[];

  constructor(
    private readonly db: Database,
    private readonly table: string,
    private readonly columns: Record<string, Column<T>> = {},
    private readonly orderBy = "rowid",
  ) {
    this.cols = Object.keys(columns);
    const defs = this.cols.map((c) => `${c} ${columns[c]!.type}`).join(", ");
    db.exec(
      `CREATE TABLE IF NOT EXISTS ${table} (id TEXT PRIMARY KEY, ${defs}${defs ? "," : ""} doc TEXT NOT NULL)`,
    );
  }

  put(doc: T): T {
    const names = ["id", ...this.cols, "doc"];
    const values = [doc.id, ...this.cols.map((c) => this.columns[c]!.get(doc) ?? null), JSON.stringify(doc)];
    this.db
      .prepare(
        `INSERT INTO ${this.table} (${names.join(",")}) VALUES (${names.map(() => "?").join(",")})
         ON CONFLICT(id) DO UPDATE SET ${names
           .slice(1)
           .map((n) => `${n}=excluded.${n}`)
           .join(",")}`,
      )
      .run(...values);
    return doc;
  }

  get(id: string): T | null {
    const row = this.db.prepare(`SELECT doc FROM ${this.table} WHERE id = ?`).get(id) as { doc: string } | undefined;
    return row ? (JSON.parse(row.doc) as T) : null;
  }

  list(where = "", ...params: (string | number)[]): T[] {
    const rows = this.db
      .prepare(`SELECT doc FROM ${this.table} ${where ? `WHERE ${where}` : ""} ORDER BY ${this.orderBy}`)
      .all(...params) as { doc: string }[];
    return rows.map((r) => JSON.parse(r.doc) as T);
  }

  delete(id: string): boolean {
    return this.db.prepare(`DELETE FROM ${this.table} WHERE id = ?`).run(id).changes > 0;
  }

  deleteWhere(where: string, ...params: (string | number)[]): number {
    return this.db.prepare(`DELETE FROM ${this.table} WHERE ${where}`).run(...params).changes;
  }
}

/** Key to JSON document. */
export class KvStore<T> {
  constructor(
    private readonly db: Database,
    private readonly table: string,
  ) {
    db.exec(`CREATE TABLE IF NOT EXISTS ${table} (k TEXT PRIMARY KEY, doc TEXT NOT NULL)`);
  }

  get(key: string): T | null {
    const row = this.db.prepare(`SELECT doc FROM ${this.table} WHERE k = ?`).get(key) as { doc: string } | undefined;
    return row ? (JSON.parse(row.doc) as T) : null;
  }

  put(key: string, doc: T): void {
    this.db
      .prepare(`INSERT INTO ${this.table} (k, doc) VALUES (?, ?) ON CONFLICT(k) DO UPDATE SET doc=excluded.doc`)
      .run(key, JSON.stringify(doc));
  }

  delete(key: string): void {
    this.db.prepare(`DELETE FROM ${this.table} WHERE k = ?`).run(key);
  }

  clear(): void {
    this.db.exec(`DELETE FROM ${this.table}`);
  }
}
