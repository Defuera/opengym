import { Hono } from "hono";
import { type Session, SessionSchema } from "../schema";
import type { AppContext } from "../app-context";
import { HttpError, jsonBody, notFound } from "./http";

export function sessionRoutes({ repos, refresher }: AppContext) {
  const r = new Hono();

  r.get("/", (c) => {
    const raw = c.req.query("since");
    const since = raw === undefined ? undefined : Number(raw);
    if (since !== undefined && !Number.isFinite(since)) throw new HttpError(400, "since must be a number");
    return c.json({ sessions: repos.sessions.list(since) });
  });

  r.put("/:id", async (c) => {
    const session: Session = await jsonBody(c, SessionSchema);
    if (session.id !== c.req.param("id")) throw new HttpError(400, "id in path and body differ");
    repos.sessions.upsert(session);
    refresher.sessionWritten(session);
    return c.json({ session });
  });

  r.delete("/:id", (c) => {
    const id = c.req.param("id");
    if (!repos.sessions.delete(id)) throw notFound("session");
    refresher.sessionDeleted(id);
    return c.json({ ok: true });
  });

  r.get("/:id/review", (c) => c.json({ review: repos.reviews.get(c.req.param("id")) }));
  return r;
}
