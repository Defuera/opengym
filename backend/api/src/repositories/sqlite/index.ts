import { mkdirSync } from "node:fs";
import path from "node:path";
import Database from "better-sqlite3";
import type { Repositories } from "../types";
import { SqliteFileRepository } from "./file-repo";
import {
  SqliteContextRepository,
  SqliteGoalRepository,
  SqliteReviewRepository,
  SqliteSessionRepository,
} from "./log-repos";
import {
  SqliteDashboardSpecRepository,
  SqliteImportRepository,
  SqlitePlanRepository,
  SqlitePredictionRepository,
} from "./proposal-repos";
import { SqliteThreadRepository } from "./thread-repo";

/** dbPath may be ":memory:" (files then go to filesDir, which must be given). */
export function createSqliteRepositories(dbPath: string, filesDir: string): Repositories {
  if (dbPath !== ":memory:") mkdirSync(path.dirname(path.resolve(dbPath)), { recursive: true });
  const db = new Database(dbPath);
  // WAL needs shared memory and file locks; on network/FUSE mounts (Cloud Storage via gcsfuse) use DELETE.
  const mode = (process.env.SQLITE_JOURNAL_MODE ?? "WAL").trim().toUpperCase();
  if (!["WAL", "DELETE", "TRUNCATE", "PERSIST", "MEMORY", "OFF"].includes(mode)) {
    throw new Error(`SQLITE_JOURNAL_MODE=${mode} is not a valid SQLite journal mode`);
  }
  db.pragma(`journal_mode = ${mode}`);
  return {
    sessions: new SqliteSessionRepository(db),
    goals: new SqliteGoalRepository(db),
    context: new SqliteContextRepository(db),
    threads: new SqliteThreadRepository(db),
    files: new SqliteFileRepository(db, filesDir),
    imports: new SqliteImportRepository(db),
    plans: new SqlitePlanRepository(db),
    dashboards: new SqliteDashboardSpecRepository(db),
    predictions: new SqlitePredictionRepository(db),
    reviews: new SqliteReviewRepository(db),
    close: () => db.close(),
  };
}
