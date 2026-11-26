import type { MutationCtx, QueryCtx } from "../_generated/server";

/** The settings row of a user, or null before the first write. */
export async function settingsRow(ctx: QueryCtx | MutationCtx, userId: string) {
  return ctx.db.query("settings").withIndex("by_user", (q) => q.eq("userId", userId)).unique();
}

/** Patch the settings row of a user; create it when missing. `undefined` values remove a field. */
export async function patchSettings(ctx: MutationCtx, userId: string, patch: Record<string, unknown>) {
  const row = await settingsRow(ctx, userId);
  if (row) await ctx.db.patch(row._id, patch);
  else await ctx.db.insert("settings", { ...Object.fromEntries(Object.entries(patch).filter(([, v]) => v !== undefined)), userId });
}
