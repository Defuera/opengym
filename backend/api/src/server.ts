import "dotenv/config";
import { networkInterfaces } from "node:os";
import { serve } from "@hono/node-server";
import { ConfigError, createProviderFromEnv } from "./ai/factory";
import { consoleLogger, createAiRunner } from "./ai/run-job";
import { buildApp } from "./app";
import { loadServerConfig } from "./config";
import { createSqliteRepositories } from "./repositories/sqlite";
import { createTaskQueue } from "./services/queue";

const VERSION = "1.0.0";

function lanUrls(port: number): string[] {
  return Object.values(networkInterfaces())
    .flat()
    .filter((i) => i && i.family === "IPv4" && !i.internal)
    .map((i) => `http://${i!.address}:${port}`);
}

function main() {
  let provider;
  try {
    provider = createProviderFromEnv(process.env);
  } catch (e) {
    if (e instanceof ConfigError) {
      console.error(`Startup error: ${e.message}`);
      process.exit(1);
    }
    throw e;
  }
  const cfg = loadServerConfig(process.env);
  const repos = createSqliteRepositories(cfg.dbPath, cfg.filesDir);
  const { app } = buildApp({
    token: cfg.token,
    version: VERSION,
    repos,
    ai: createAiRunner(provider, consoleLogger),
    queue: createTaskQueue(consoleLogger),
    logger: consoleLogger,
    now: () => Date.now(),
  });

  const server = serve({ fetch: app.fetch, hostname: cfg.host, port: cfg.port }, (info) => {
    console.log(`OpenGym backend ${VERSION} listening on ${cfg.host}:${info.port}`);
    console.log(`AI provider: ${provider?.name ?? "none (plain-code fallbacks only)"}`);
    console.log("Use one of these URLs in the phone app:");
    for (const u of lanUrls(info.port)) console.log(`  ${u}`);
    console.log(`  http://localhost:${info.port}  (this machine only)`);
    console.log(`Token: ${cfg.token}${cfg.tokenGenerated ? "   (generated for this run; set APP_TOKEN in .env to keep it)" : ""}`);
  });
  const stop = () => {
    server.close();
    repos.close();
    process.exit(0);
  };
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);
}

process.on("unhandledRejection", (e) => console.error("[unhandledRejection]", e));
main();
