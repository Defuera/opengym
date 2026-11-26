import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireUser } from "../lib/auth";

/** Threads, newest first, with summary, lastMessage and the reply status (`idle` | `thinking` | `failed` + `error`). */
export const list = query({
  args: { token: v.string() },
  handler: async (ctx, { token }) => {
    const userId = await requireUser(ctx, token);
    return ctx.db.query("threads").withIndex("by_updatedAt").order("desc").collect();
  },
});
