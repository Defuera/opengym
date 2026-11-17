import type { Context } from "hono";
import type { z } from "zod";

export class HttpError extends Error {
  constructor(
    public status: 400 | 401 | 404 | 413,
    message: string,
  ) {
    super(message);
  }
}

export function parseWith<T>(schema: z.ZodType<T>, data: unknown): T {
  const r = schema.safeParse(data);
  if (!r.success) {
    const i = r.error.issues[0];
    throw new HttpError(400, `${i?.path.join(".") || "body"}: ${i?.message ?? "invalid"}`);
  }
  return r.data;
}

export async function jsonBody<T>(c: Context, schema: z.ZodType<T>): Promise<T> {
  let raw: unknown;
  try {
    raw = await c.req.json();
  } catch {
    throw new HttpError(400, "body must be JSON");
  }
  return parseWith(schema, raw);
}

export const notFound = (what: string) => new HttpError(404, `${what} not found`);
