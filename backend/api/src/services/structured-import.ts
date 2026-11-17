import { randomUUID } from "node:crypto";
import type { z } from "zod";
import { type ContextInput, ContextInputSchema, type GoalInput, GoalInputSchema, type Session, SessionSchema } from "../schema";
import { StructuredImportBodySchema, StructuredSessionSchema } from "../schema/structured-import";

export class StructuredImportError extends Error {}

export interface StructuredImport {
  sessions: Session[];
  goals: GoalInput[];
  context: ContextInput[];
  note?: string;
}

function fail(where: string, e: z.ZodError): never {
  const i = e.issues[0];
  const path = i?.path.join(".");
  throw new StructuredImportError(`${where}${path && i?.code !== "custom" ? `.${path}` : ""}: ${i?.message ?? "invalid"}`);
}

/** Validates the whole body before anything is written. Throws StructuredImportError naming the first bad item. */
export function parseStructuredImport(raw: unknown, jobId: string): StructuredImport {
  const body = StructuredImportBodySchema.safeParse(raw);
  if (!body.success) fail("body", body.error);
  const b = body.data!;
  const sessions = b.sessions.map((x, i) => {
    const d = StructuredSessionSchema.safeParse(x);
    if (!d.success) fail(`sessions[${i}]`, d.error);
    const s = SessionSchema.safeParse({ ...d.data, id: d.data!.id ?? randomUUID(), source: "import", importId: jobId });
    if (!s.success) fail(`sessions[${i}]`, s.error);
    return s.data!;
  });
  const goals = b.goals.map((x, i) => {
    const g = GoalInputSchema.safeParse(x);
    if (!g.success) fail(`goals[${i}]`, g.error);
    return g.data!;
  });
  const context = b.context.map((x, i) => {
    const c = ContextInputSchema.safeParse(x);
    if (!c.success) fail(`context[${i}]`, c.error);
    return c.data!;
  });
  return { sessions, goals, context, note: b.note };
}
