import { v } from "convex/values";
import { internal } from "../_generated/api";
import { mutation } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { START_REQUEST_MAX_NAME, START_REQUEST_MAX_TEXT, START_REQUEST_PURGE_BATCH, START_REQUEST_TTL_MS } from "../lib/constants";
import { startRequestById } from "../lib/db";

/**
 * A typed "Start session" request (ADR-016). Idempotent by the client-made `requestId`: a resend changes nothing and
 * schedules nothing. Stores `{requestId, text?, name?, status: "pending"}` and schedules the interpret_request job
 * (jobs/startRequest:build). This is not a fact: the AI only proposes; the app saves a session after the user starts it.
 * `name` (optional, 1..40) is the fixed session name: the proposal type is always this name. `text` (optional, max 200)
 * is the wish. At least one of the two is required, so an old client that sends only `text` keeps working.
 * With `mode: "today"` the coach picks the one session for today: `text` is the optional wish, `name` must be absent, and
 * `hintType` (1..40) / `hintFocus` (max 40) carry the pick the app showed. Requests older than one day are removed here.
 * Returns the requestId.
 */
export const request = mutation({
  args: {
    token: v.string(),
    requestId: v.string(),
    text: v.optional(v.string()),
    name: v.optional(v.string()),
    mode: v.optional(v.literal("today")),
    hintType: v.optional(v.string()),
    hintFocus: v.optional(v.string()),
  },
  handler: async (ctx, { token, requestId, text, name, mode, hintType, hintFocus }): Promise<string> => {
    requireToken(token);
    const id = requestId.trim();
    if (id.length < 1 || id.length > 100) throw new Error("requestId must be 1..100 characters");
    const cleanName = name?.trim();
    if (name !== undefined && (!cleanName || cleanName.length > START_REQUEST_MAX_NAME)) throw new Error(`name must be 1..${START_REQUEST_MAX_NAME} characters`);
    const clean = text?.trim();
    const cleanHintType = hintType?.trim();
    const cleanHintFocus = hintFocus?.trim();
    if (mode === "today") {
      // "Today" mode: the coach picks. The wish is optional, a name is not allowed, the hint is the pick the user saw.
      if (name !== undefined) throw new Error("name must be absent in today mode");
      if (clean !== undefined && clean.length > START_REQUEST_MAX_TEXT) throw new Error(`text must be 0..${START_REQUEST_MAX_TEXT} characters`);
      if (hintType !== undefined && (!cleanHintType || cleanHintType.length > START_REQUEST_MAX_NAME)) throw new Error(`hintType must be 1..${START_REQUEST_MAX_NAME} characters`);
      if (hintFocus !== undefined && cleanHintFocus!.length > START_REQUEST_MAX_NAME) throw new Error(`hintFocus must be 0..${START_REQUEST_MAX_NAME} characters`);
      if (hintFocus !== undefined && hintType === undefined) throw new Error("hintFocus needs hintType");
    } else if (hintType !== undefined || hintFocus !== undefined) {
      throw new Error("hintType and hintFocus need mode today");
    }
    // Text is optional only when a name is given. An empty text next to a name means "no wish".
    if (text !== undefined && clean!.length > START_REQUEST_MAX_TEXT) throw new Error(`text must be 1..${START_REQUEST_MAX_TEXT} characters`);
    if (mode !== "today" && cleanName === undefined && (clean === undefined || clean.length < 1)) throw new Error(`text must be 1..${START_REQUEST_MAX_TEXT} characters (or give a name)`);
    const now = Date.now();
    const old = await ctx.db.query("startRequests").withIndex("by_createdAt", (q) => q.lt("createdAt", now - START_REQUEST_TTL_MS)).take(START_REQUEST_PURGE_BATCH);
    for (const d of old) await ctx.db.delete(d._id);
    if (await startRequestById(ctx, id)) return id;
    await ctx.db.insert("startRequests", { requestId: id, ...(clean ? { text: clean } : {}), ...(cleanName ? { name: cleanName } : {}), ...(mode === "today" ? { mode } : {}), ...(cleanHintType ? { hintType: cleanHintType } : {}), ...(cleanHintFocus ? { hintFocus: cleanHintFocus } : {}), status: "pending", createdAt: now });
    await ctx.scheduler.runAfter(0, internal.jobs.startRequest.build, { requestId: id });
    return id;
  },
});
