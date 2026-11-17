import { ConvexError } from "convex/values";
import type { z } from "zod";

/** Parse with zod; on failure throw a ConvexError the client can read (plain errors are hidden in production). */
export function parseOrThrow<T>(schema: z.ZodType<T>, value: unknown, where: string): T {
  const r = schema.safeParse(value);
  if (r.success) return r.data;
  const i = r.error.issues[0];
  const path = i?.path.join(".");
  throw new ConvexError(`${where}${path && i?.code !== "custom" ? `.${path}` : ""}: ${i?.message ?? "invalid"}`);
}
