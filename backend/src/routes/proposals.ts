import { Hono } from "hono";
import type { AppContext } from "../app-context";
import { HttpError } from "./http";

/** start, plans, dashboard: answer from stored proposals; AI only in plans/next (8 s budget). */
export function proposalRoutes({ proposals, queue, refresher, repos }: AppContext) {
  const r = new Hono();

  r.get("/start", (c) => {
    if (!repos.predictions.get()) queue.enqueue("predictions", async () => void (await proposals.refreshPredictions()));
    return c.json({ predictions: proposals.predictions() });
  });

  r.get("/plans/next", async (c) => {
    const type = c.req.query("type")?.trim();
    if (!type || type.length > 40) throw new HttpError(400, "type is required (1..40 chars)");
    return c.json({ plan: await proposals.nextPlan(type) });
  });

  r.get("/dashboard", (c) => {
    const raw = c.req.query("days") ?? "7";
    if (raw !== "7" && raw !== "30") throw new HttpError(400, "days must be 7 or 30");
    const days = Number(raw) as 7 | 30;
    const { dashboard, stored } = proposals.dashboard(days);
    if (!stored) queue.enqueue(`dashboard:${days}`, async () => void (await proposals.refreshDashboard(days)));
    return c.json({ dashboard });
  });

  void refresher;
  return r;
}
