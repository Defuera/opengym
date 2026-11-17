import { randomUUID } from "node:crypto";
import { Hono } from "hono";
import { MessageInputSchema, ThreadInputSchema } from "../schema";
import type { AppContext } from "../app-context";
import { postChatMessage } from "../services/chat";
import { jsonBody, notFound } from "./http";

export function threadRoutes(ctx: AppContext) {
  const { repos, now } = ctx;
  const r = new Hono();

  r.get("/", (c) => c.json({ threads: repos.threads.list() }));

  r.post("/", async (c) => {
    const { title } = await jsonBody(c, ThreadInputSchema);
    const t = now();
    return c.json({ thread: repos.threads.put({ id: randomUUID(), title, createdAt: t, updatedAt: t, summary: "" }) });
  });

  r.delete("/:id", (c) => {
    if (!repos.threads.delete(c.req.param("id"))) throw notFound("thread");
    return c.json({ ok: true });
  });

  r.get("/:id/messages", (c) => {
    const id = c.req.param("id");
    if (!repos.threads.get(id)) throw notFound("thread");
    return c.json({ messages: repos.threads.messages(id) });
  });

  r.post("/:id/messages", async (c) => {
    const body = await jsonBody(c, MessageInputSchema);
    const result = await postChatMessage(ctx, c.req.param("id"), body.text, body.fileIds ?? []);
    if (!result) throw notFound("thread");
    return c.json(result);
  });
  return r;
}
