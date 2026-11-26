import { ConvexError, v } from "convex/values";
import { mutation } from "../_generated/server";
import { requireUser } from "../lib/auth";
import { stableJson, withoutSystemFields } from "../lib/db";
import { markFactsChanged } from "../lib/factsChanged";
import { checkinByCheckinId, limitByLimitId, recordByRecordId } from "../lib/limitsDb";
import { parseOrThrow } from "../lib/validate";
import { CheckinSchema, LimitSchema, RecordInputSchema } from "../model/schema";
import { checkinFields, limitFields, recordFields } from "../schema";

/** Idempotent write of one limit, keyed by the client-made limitId. A change asks for a rebuild (plans read limits). */
export const save = mutation({
  args: { token: v.string(), limit: v.object(limitFields) },
  handler: async (ctx, { token, limit }) => {
    const userId = await requireUser(ctx, token);
    parseOrThrow(LimitSchema, limit, "limit");
    const old = await limitByLimitId(ctx, userId, limit.limitId);
    if (old && stableJson(withoutSystemFields(old)) === stableJson({ ...limit, userId })) return limit.limitId;
    if (old) await ctx.db.replace(old._id, { ...limit, userId });
    else await ctx.db.insert("limits", { ...limit, userId });
    await markFactsChanged(ctx, userId);
    return limit.limitId;
  },
});

/** Delete a limit with its records and check-ins. No error if it is already gone. */
export const remove = mutation({
  args: { token: v.string(), limitId: v.string() },
  handler: async (ctx, { token, limitId }) => {
    const userId = await requireUser(ctx, token);
    const old = await limitByLimitId(ctx, userId, limitId);
    if (!old) return false;
    for (const r of await ctx.db.query("records").withIndex("by_user_and_limitId", (q) => q.eq("userId", userId).eq("limitId", limitId)).collect()) await ctx.db.delete(r._id);
    for (const c of await ctx.db.query("checkins").withIndex("by_user_and_limitId", (q) => q.eq("userId", userId).eq("limitId", limitId)).collect()) await ctx.db.delete(c._id);
    await ctx.db.delete(old._id);
    await markFactsChanged(ctx, userId);
    return true;
  },
});

/** Idempotent write of one record. The text is stored word for word. Records change no read model. */
export const addRecord = mutation({
  args: { token: v.string(), record: v.object(recordFields) },
  handler: async (ctx, { token, record }) => {
    const userId = await requireUser(ctx, token);
    parseOrThrow(RecordInputSchema, record, "record");
    if (!(await limitByLimitId(ctx, userId, record.limitId))) throw new ConvexError(`limit not found: ${record.limitId}`);
    const old = await recordByRecordId(ctx, userId, record.recordId);
    if (old) await ctx.db.replace(old._id, { ...record, userId });
    else await ctx.db.insert("records", { ...record, userId });
    return record.recordId;
  },
});

/** Delete one record. No error if it is already gone. */
export const removeRecord = mutation({
  args: { token: v.string(), recordId: v.string() },
  handler: async (ctx, { token, recordId }) => {
    const userId = await requireUser(ctx, token);
    const old = await recordByRecordId(ctx, userId, recordId);
    if (!old) return false;
    await ctx.db.delete(old._id);
    return true;
  },
});

/** Idempotent write of one check-in: how the body part felt. */
export const checkin = mutation({
  args: { token: v.string(), checkin: v.object(checkinFields) },
  handler: async (ctx, { token, checkin }) => {
    const userId = await requireUser(ctx, token);
    parseOrThrow(CheckinSchema, checkin, "checkin");
    if (!(await limitByLimitId(ctx, userId, checkin.limitId))) throw new ConvexError(`limit not found: ${checkin.limitId}`);
    const old = await checkinByCheckinId(ctx, userId, checkin.checkinId);
    if (old) await ctx.db.replace(old._id, { ...checkin, userId });
    else await ctx.db.insert("checkins", { ...checkin, userId });
    return checkin.checkinId;
  },
});
