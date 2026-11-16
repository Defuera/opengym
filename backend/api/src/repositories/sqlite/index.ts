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
  db.pragma("journal_mode = WAL");
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
