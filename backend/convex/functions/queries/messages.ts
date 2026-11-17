import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireToken } from "../lib/auth";

/** Messages of one thread, oldest first. Subscribe to it: the assistant message arrives live. */
export const list = query({
  args: { token: v.string(), threadId: v.string() },
  handler: async (ctx, { token, threadId }) => {
    requireToken(token);
    return ctx.db.query("messages").withIndex("by_threadId", (q) => q.eq("threadId", threadId)).order("asc").collect();
  },
});
