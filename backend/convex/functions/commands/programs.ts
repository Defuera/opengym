import { ConvexError, v } from "convex/values";
import { mutation } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { markFactsChanged } from "../lib/factsChanged";
import { programStatus } from "../lib/programFields";
import { programByProgramId } from "../lib/programsDb";

/** Pauses, resumes or ends a program (`rev` + 1). A paused or done program has no `next` session in queries/programs:list. Returns null. */
export const setStatus = mutation({
  args: { token: v.string(), programId: v.string(), status: programStatus },
  handler: async (ctx, { token, programId, status }): Promise<null> => {
    requireToken(token);
    const p = await programByProgramId(ctx, programId);
    if (!p) throw new ConvexError("program not found");
    if (p.status !== status) await ctx.db.patch(p._id, { status, rev: p.rev + 1, updatedAt: Date.now() });
    return null;
  },
});

/**
 * Deletes a program the way a session is deleted (ADR-020): it only MARKS the row (`deletedAt` = now); every read leaves it out and
 * jobs/purge erases it later. The logged sessions of the program stay: they are facts. Idempotent; an unknown or marked program is
 * left alone. Returns null.
 */
export const remove = mutation({
  args: { token: v.string(), programId: v.string() },
  handler: async (ctx, { token, programId }): Promise<null> => {
    requireToken(token);
    const p = await programByProgramId(ctx, programId);
    if (!p) return null;
    await ctx.db.patch(p._id, { deletedAt: Date.now() });
    await markFactsChanged(ctx);
    return null;
  },
});
