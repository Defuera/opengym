import { ConvexError, v } from "convex/values";
import { mutation } from "../_generated/server";
import { requireUser } from "../lib/auth";
import { goalByGoalId } from "../lib/db";
import { markFactsChanged } from "../lib/factsChanged";
import { goalKind, goalStatus } from "../lib/validators";
import { parseOrThrow } from "../lib/validate";
import { GoalInputSchema, GoalPatchSchema } from "../model/schema";

/** Create a goal with a client-made goalId. A plain write: the app makes goals through the chat draft (ADR-032), not here. Resending the same goalId changes nothing. */
export const create = mutation({
  args: {
    token: v.string(),
    goalId: v.string(),
    title: v.string(),
    kind: goalKind,
    exercise: v.optional(v.string()),
    targetKg: v.optional(v.number()),
    sessionsPerWeek: v.optional(v.number()),
  },
  handler: async (ctx, { token, goalId, ...input }) => {
    const userId = await requireUser(ctx, token);
    if (!goalId || goalId.length > 100) throw new ConvexError("goalId: must be 1 to 100 characters");
    const valid = parseOrThrow(GoalInputSchema, input, "goal");
    if (await goalByGoalId(ctx, userId, goalId)) return goalId;
    await ctx.db.insert("goals", { userId, goalId, ...valid, status: "active", source: "user", createdAt: Date.now() });
    await markFactsChanged(ctx, userId);
    return goalId;
  },
});

/** Change title, kind, targets or status. Only the fields you send change. */
export const update = mutation({
  args: {
    token: v.string(),
    goalId: v.string(),
    title: v.optional(v.string()),
    kind: v.optional(goalKind),
    exercise: v.optional(v.string()),
    targetKg: v.optional(v.number()),
    sessionsPerWeek: v.optional(v.number()),
    status: v.optional(goalStatus),
  },
  handler: async (ctx, { token, goalId, ...patch }) => {
    const userId = await requireUser(ctx, token);
    const valid = parseOrThrow(GoalPatchSchema, patch, "goal");
    const old = await goalByGoalId(ctx, userId, goalId);
    if (!old) throw new ConvexError(`goal not found: ${goalId}`);
    // A new title makes the old structure stale: it is cleared unless sent now. No AI reads it again (ADR-032, step D): the coach drafts a changed goal in the chat.
    const retitled = valid.title !== undefined && valid.title !== old.title;
    await ctx.db.patch(old._id, retitled ? { kind: "custom", exercise: undefined, targetKg: undefined, sessionsPerWeek: undefined, ...valid } : valid);
    await markFactsChanged(ctx, userId);
    return goalId;
  },
});

/** Delete a goal. No error if it is already gone. */
export const remove = mutation({
  args: { token: v.string(), goalId: v.string() },
  handler: async (ctx, { token, goalId }) => {
    const userId = await requireUser(ctx, token);
    const old = await goalByGoalId(ctx, userId, goalId);
    if (!old) return false;
    await ctx.db.delete(old._id);
    await markFactsChanged(ctx, userId);
    return true;
  },
});
