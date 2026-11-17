import type { MutationCtx, QueryCtx } from "../_generated/server";

/** The single settings row, or null before the first write. */
export async function settingsRow(ctx: QueryCtx | MutationCtx) {
  return ctx.db.query("settings").first();
}

/** Patch the single settings row; create it when missing. `undefined` values remove a field. */
export async function patchSettings(ctx: MutationCtx, patch: Record<string, unknown>) {
  const row = await settingsRow(ctx);
  if (row) await ctx.db.patch(row._id, patch);
  else await ctx.db.insert("settings", Object.fromEntries(Object.entries(patch).filter(([, v]) => v !== undefined)));
}
