import type { Database } from "better-sqlite3";
import type { Message, Thread } from "../../schema";
import type { ThreadRepository } from "../types";
import { DocStore } from "./doc-store";

export class SqliteThreadRepository implements ThreadRepository {
  private readonly threads: DocStore<Thread>;
  private readonly msgs: DocStore<Message>;

  constructor(db: Database) {
    this.threads = new DocStore<Thread>(
      db,
      "threads",
      { updated_at: { type: "INTEGER", get: (t) => t.updatedAt } },
      "updated_at DESC, rowid DESC",
    );
    this.msgs = new DocStore<Message>(
      db,
      "messages",
      {
        thread_id: { type: "TEXT", get: (m) => m.threadId },
        created_at: { type: "INTEGER", get: (m) => m.createdAt },
      },
      "created_at, rowid",
    );
  }

  list() {
    return this.threads.list();
  }
  get(id: string) {
    return this.threads.get(id);
  }
  put(t: Thread) {
    return this.threads.put(t);
  }
  delete(id: string) {
    this.msgs.deleteWhere("thread_id = ?", id);
    return this.threads.delete(id);
  }
  messages(threadId: string) {
    return this.msgs.list("thread_id = ?", threadId);
  }
  addMessage(m: Message) {
    return this.msgs.put(m);
  }
}
