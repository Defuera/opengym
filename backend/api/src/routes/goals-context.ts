import { randomUUID } from "node:crypto";
import { Hono } from "hono";
import { ContextInputSchema, ContextPatchSchema, GoalInputSchema, GoalPatchSchema } from "../schema";
import type { AppContext } from "../app-context";
import { jsonBody, notFound } from "./http";

export function goalRoutes({ repos, refresher, now }: AppContext) {
  const r = new Hono();
  r.get("/", (c) => c.json({ goals: repos.goals.list() }));

  r.post("/", async (c) => {
    const input = await jsonBody(c, GoalInputSchema);
    const goal = repos.goals.put({ ...input, id: randomUUID(), status: "active", source: "user", createdAt: now() });
    refresher.factsChanged();
    return c.json({ goal });
  });

  r.patch("/:id", async (c) => {
    const existing = repos.goals.get(c.req.param("id"));
    if (!existing) throw notFound("goal");
    const patch = await jsonBody(c, GoalPatchSchema);
    const goal = repos.goals.put({ ...existing, ...patch });
    refresher.factsChanged();
    return c.json({ goal });
  });

  r.delete("/:id", (c) => {
    if (!repos.goals.delete(c.req.param("id"))) throw notFound("goal");
    refresher.factsChanged();
    return c.json({ ok: true });
  });
  return r;
}

export function contextRoutes({ repos, refresher, now }: AppContext) {
  const r = new Hono();
  r.get("/", (c) => c.json({ items: repos.context.list() }));

  r.post("/", async (c) => {
    const input = await jsonBody(c, ContextInputSchema);
    const item = repos.context.put({ ...input, id: randomUUID(), active: true, source: "user", createdAt: now() });
    refresher.factsChanged();
    return c.json({ item });
  });

  r.patch("/:id", async (c) => {
    const existing = repos.context.get(c.req.param("id"));
    if (!existing) throw notFound("context item");
    const patch = await jsonBody(c, ContextPatchSchema);
    const item = repos.context.put({ ...existing, ...patch });
    refresher.factsChanged();
    return c.json({ item });
  });

  r.delete("/:id", (c) => {
    if (!repos.context.delete(c.req.param("id"))) throw notFound("context item");
    refresher.factsChanged();
    return c.json({ ok: true });
  });
  return r;
}
