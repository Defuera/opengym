import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { createSqliteRepositories } from "./sqlite";
import type { Repositories } from "./types";

/** Temp-file repositories for tests. Call cleanup() when done. */
export function createTempRepositories(): { repos: Repositories; cleanup: () => void } {
  const dir = mkdtempSync(path.join(tmpdir(), "opengym-"));
  const repos = createSqliteRepositories(path.join(dir, "test.db"), path.join(dir, "files"));
  return {
    repos,
    cleanup: () => {
      repos.close();
      rmSync(dir, { recursive: true, force: true });
    },
  };
}
