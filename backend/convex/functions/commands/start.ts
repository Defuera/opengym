import { v } from "convex/values";
import { internal } from "../_generated/api";
import { mutation } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { START_REQUEST_MAX_TEXT, START_REQUEST_PURGE_BATCH, START_REQUEST_TTL_MS } from "../lib/constants";
import { startRequestById } from "../lib/db";

/**
 * A typed "Start session" request (ADR-016). Idempotent by the client-made `requestId`: a resend changes nothing and
 * schedules nothing. Stores `{requestId, text, status: "pending"}` and schedules the interpret_request job
 * (jobs/startRequest:build). This is not a fact: the AI only proposes; the app saves a session after the user starts it.
 * `text` is 1..200 characters (after trimming). Requests older than one day are removed here.
 * Returns the requestId.
 */
export const request = mutation({
  args: { token: v.string(), requestId: v.string(), text: v.string() },
  handler: async (ctx, { token, requestId, text }): Promise<string> => {
    requireToken(token);
    const id = requestId.trim();
    if (id.length < 1 || id.length > 100) throw new Error("requestId must be 1..100 characters");
    const clean = text.trim();
    if (clean.length < 1 || clean.length > START_REQUEST_MAX_TEXT) throw new Error(`text must be 1..${START_REQUEST_MAX_TEXT} characters`);
    const now = Date.now();
    const old = await ctx.db.query("startRequests").withIndex("by_createdAt", (q) => q.lt("createdAt", now - START_REQUEST_TTL_MS)).take(START_REQUEST_PURGE_BATCH);
    for (const d of old) await ctx.db.delete(d._id);
    if (await startRequestById(ctx, id)) return id;
    await ctx.db.insert("startRequests", { requestId: id, text: clean, status: "pending", createdAt: now });
    await ctx.scheduler.runAfter(0, internal.jobs.startRequest.build, { requestId: id });
    return id;
  },
});
