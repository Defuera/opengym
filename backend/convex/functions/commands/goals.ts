import { ConvexError, v } from "convex/values";
import { internal } from "../_generated/api";
import { mutation } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { goalByGoalId } from "../lib/db";
import { markFactsChanged } from "../lib/factsChanged";
import { goalKind, goalStatus } from "../lib/validators";
import { parseOrThrow } from "../lib/validate";
import { GoalInputSchema, GoalPatchSchema } from "../model/schema";

/** Create a goal with a client-made goalId. Resending the same goalId changes nothing. */
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
    requireToken(token);
    if (!goalId || goalId.length > 100) throw new ConvexError("goalId: must be 1 to 100 characters");
    const valid = parseOrThrow(GoalInputSchema, input, "goal");
    if (await goalByGoalId(ctx, goalId)) return goalId;
    await ctx.db.insert("goals", { goalId, ...valid, status: "active", source: "user", createdAt: Date.now() });
    await markFactsChanged(ctx);
    // The goal is stored as typed. The AI reads its structure a moment later (parse_goal); nothing waits for it.
    await ctx.scheduler.runAfter(0, internal.jobs.parseGoal.run, { goalId, text: valid.title });
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
    requireToken(token);
    const valid = parseOrThrow(GoalPatchSchema, patch, "goal");
    const old = await goalByGoalId(ctx, goalId);
    if (!old) throw new ConvexError(`goal not found: ${goalId}`);
    // A new title makes the old structure stale: it is cleared (unless sent now) and read again from the new text.
    const retitled = valid.title !== undefined && valid.title !== old.title;
    await ctx.db.patch(old._id, retitled ? { kind: "custom", exercise: undefined, targetKg: undefined, sessionsPerWeek: undefined, ...valid } : valid);
    await markFactsChanged(ctx);
    if (retitled) await ctx.scheduler.runAfter(0, internal.jobs.parseGoal.run, { goalId, text: valid.title! });
    return goalId;
  },
});

/** Delete a goal. No error if it is already gone. */
export const remove = mutation({
  args: { token: v.string(), goalId: v.string() },
  handler: async (ctx, { token, goalId }) => {
    requireToken(token);
    const old = await goalByGoalId(ctx, goalId);
    if (!old) return false;
    await ctx.db.delete(old._id);
    await markFactsChanged(ctx);
    return true;
  },
});
