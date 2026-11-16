import { timingSafeEqual } from "node:crypto";
import { Hono } from "hono";
import type { AppContext, AppDeps } from "./app-context";
import { describeJobs } from "./ai/jobs";
import { createImportRunner } from "./services/import-runner";
import { createProposalService } from "./services/proposals";
import { createRefresher } from "./services/refresh";
import { HttpError } from "./routes/http";
import { fileRoutes, importRoutes } from "./routes/files-import";
import { contextRoutes, goalRoutes } from "./routes/goals-context";
import { proposalRoutes } from "./routes/proposals";
import { sessionRoutes } from "./routes/sessions";
import { threadRoutes } from "./routes/threads";

function tokenMatches(given: string, expected: string): boolean {
  const a = Buffer.from(given);
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}

export function buildApp(deps: AppDeps): { app: Hono; ctx: AppContext } {
  const proposals = createProposalService(deps.repos, deps.ai, deps.now);
  const refresher = createRefresher(deps.repos, proposals, deps.ai, deps.queue);
  const importRunner = createImportRunner({ ...deps, refresher });
  const ctx: AppContext = { ...deps, proposals, refresher, importRunner };

  const app = new Hono();

  app.get("/v1/health", (c) =>
    c.json({ ok: true, provider: deps.ai.provider?.name ?? "none", aiConfigured: deps.ai.provider !== null, version: deps.version }),
  );

  app.use("/v1/*", async (c, next) => {
    const m = /^Bearer (.+)$/.exec(c.req.header("authorization") ?? "");
    if (!m || !tokenMatches(m[1]!, deps.token)) throw new HttpError(401, "unauthorized");
    await next();
  });

  app.route("/v1/sessions", sessionRoutes(ctx));
  app.route("/v1", proposalRoutes(ctx));
  app.route("/v1/goals", goalRoutes(ctx));
  app.route("/v1/context", contextRoutes(ctx));
  app.route("/v1/threads", threadRoutes(ctx));
  app.route("/v1/files", fileRoutes(ctx));
  app.route("/v1/import", importRoutes(ctx));
  app.get("/v1/ai/functions", (c) => c.json({ functions: describeJobs() }));

  app.notFound((c) => c.json({ error: "not found" }, 404));
  app.onError((err, c) => {
    if (err instanceof HttpError) return c.json({ error: err.message }, err.status);
    deps.logger.error(`[http] ${c.req.method} ${c.req.path}: ${err.stack ?? err.message}`);
    return c.json({ error: "internal error" }, 500);
  });

  return { app, ctx };
}
