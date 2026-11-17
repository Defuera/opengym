import { randomBytes } from "node:crypto";
import path from "node:path";

export interface ServerConfig {
  token: string;
  tokenGenerated: boolean;
  host: string;
  port: number;
  dbPath: string;
  filesDir: string;
}

export function loadServerConfig(env: Record<string, string | undefined>): ServerConfig {
  const given = env.APP_TOKEN?.trim();
  const dbPath = env.DB_PATH?.trim() || "./data/opengym.db";
  return {
    token: given || randomBytes(18).toString("base64url"),
    tokenGenerated: !given,
    host: env.HOST?.trim() || "0.0.0.0",
    port: Number(env.PORT) || 8787,
    dbPath,
    filesDir: path.join(path.dirname(path.resolve(dbPath)), "files"),
  };
}
