import { v } from "convex/values";
import { internal } from "../_generated/api";
import { mutation } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { START_REQUEST_MAX_NAME, START_REQUEST_MAX_TEXT, START_REQUEST_PURGE_BATCH, START_REQUEST_TTL_MS } from "../lib/constants";
import { startRequestById } from "../lib/db";

/**
 * A "Start session" request (ADR-016). Idempotent by the client-made `requestId`: a resend changes nothing and
 * schedules nothing. Stores `{requestId, text?, name?, status: "pending"}` and schedules the build_session job
 * (jobs/startRequest:build). This is not a fact: the AI only proposes; the app saves a session after the user starts it.
 * `name` (optional, 1..40) is the fixed session name: the proposal type is always this name. `text` (optional, max 200)
 * is the note for today, or, with no name, the request. At least one of the two is required.
 * The Start tab sends `name` (the activity the user chose) and the optional note as `text`; "Other" sends only `text`
 * (what the user wants to do) and the coach names the activity. In both cases the coach decides the focus and the plan.
 * The old "today" mode (`mode`, `hintType`, `hintFocus`) is gone. Requests older than one day are removed here.
 * Returns the requestId.
 */
export const request = mutation({
  args: {
    token: v.string(),
    requestId: v.string(),
    text: v.optional(v.string()),
    name: v.optional(v.string()),
  },
  handler: async (ctx, { token, requestId, text, name }): Promise<string> => {
    requireToken(token);
    const id = requestId.trim();
    if (id.length < 1 || id.length > 100) throw new Error("requestId must be 1..100 characters");
    const cleanName = name?.trim();
    if (name !== undefined && (!cleanName || cleanName.length > START_REQUEST_MAX_NAME)) throw new Error(`name must be 1..${START_REQUEST_MAX_NAME} characters`);
    const clean = text?.trim();
    // Text is optional only when a name is given. An empty text next to a name means "no wish".
    if (text !== undefined && clean!.length > START_REQUEST_MAX_TEXT) throw new Error(`text must be 1..${START_REQUEST_MAX_TEXT} characters`);
    if (cleanName === undefined && (clean === undefined || clean.length < 1)) throw new Error(`text must be 1..${START_REQUEST_MAX_TEXT} characters (or give a name)`);
    const now = Date.now();
    const old = await ctx.db.query("startRequests").withIndex("by_createdAt", (q) => q.lt("createdAt", now - START_REQUEST_TTL_MS)).take(START_REQUEST_PURGE_BATCH);
    for (const d of old) await ctx.db.delete(d._id);
    if (await startRequestById(ctx, id)) return id;
    await ctx.db.insert("startRequests", { requestId: id, ...(clean ? { text: clean } : {}), ...(cleanName ? { name: cleanName } : {}), status: "pending", createdAt: now });
    await ctx.scheduler.runAfter(0, internal.jobs.startRequest.build, { requestId: id });
    return id;
  },
});
