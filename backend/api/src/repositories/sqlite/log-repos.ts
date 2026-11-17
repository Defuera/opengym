import type { Database } from "better-sqlite3";
import type { ContextItem, Goal, Review, Session } from "../../schema";
import type {
  ContextRepository,
  GoalRepository,
  ReviewRepository,
  SessionRepository,
} from "../types";
import { DocStore, KvStore } from "./doc-store";

export class SqliteSessionRepository implements SessionRepository {
  private readonly store: DocStore<Session>;

  constructor(db: Database) {
    this.store = new DocStore<Session>(
      db,
      "sessions",
      {
        ended_at: { type: "INTEGER", get: (s) => s.endedAt },
        import_id: { type: "TEXT", get: (s) => s.importId },
      },
      "ended_at, rowid",
    );
  }

  upsert(s: Session) {
    return this.store.put(s);
  }
  get(id: string) {
    return this.store.get(id);
  }
  delete(id: string) {
    return this.store.delete(id);
  }
  list(since?: number) {
    return since === undefined ? this.store.list() : this.store.list("ended_at > ?", since);
  }
  deleteByImport(importId: string) {
    return this.store.deleteWhere("import_id = ?", importId);
  }
}

export class SqliteGoalRepository implements GoalRepository {
  private readonly store: DocStore<Goal>;

  constructor(db: Database) {
    this.store = new DocStore<Goal>(
      db,
      "goals",
      {
        created_at: { type: "INTEGER", get: (g) => g.createdAt },
        import_id: { type: "TEXT", get: (g) => g.importId },
      },
      "created_at, rowid",
    );
  }

  list() {
    return this.store.list();
  }
  get(id: string) {
    return this.store.get(id);
  }
  put(g: Goal) {
    return this.store.put(g);
  }
  delete(id: string) {
    return this.store.delete(id);
  }
  deleteByImport(importId: string) {
    return this.store.deleteWhere("import_id = ?", importId);
  }
}

export class SqliteContextRepository implements ContextRepository {
  private readonly store: DocStore<ContextItem>;

  constructor(db: Database) {
    this.store = new DocStore<ContextItem>(
      db,
      "context_items",
      {
        created_at: { type: "INTEGER", get: (c) => c.createdAt },
        import_id: { type: "TEXT", get: (c) => c.importId },
      },
      "created_at, rowid",
    );
  }

  list() {
    return this.store.list();
  }
  get(id: string) {
    return this.store.get(id);
  }
  put(c: ContextItem) {
    return this.store.put(c);
  }
  delete(id: string) {
    return this.store.delete(id);
  }
  deleteByImport(importId: string) {
    return this.store.deleteWhere("import_id = ?", importId);
  }
}

export class SqliteReviewRepository implements ReviewRepository {
  private readonly kv: KvStore<Review>;

  constructor(db: Database) {
    this.kv = new KvStore<Review>(db, "reviews");
  }

  get(sessionId: string) {
    return this.kv.get(sessionId);
  }
  put(r: Review) {
    this.kv.put(r.sessionId, r);
    return r;
  }
  delete(sessionId: string) {
    this.kv.delete(sessionId);
  }
}
