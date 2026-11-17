import { v } from "convex/values";
import { internalQuery, query } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { settingsRow } from "../lib/settingsDb";
import { envInfo } from "../model/ai/factory";

/** The model the owner chose in Settings, or null. Read by every AI job (lib/ai:providerFor). */
export const override = internalQuery({
  args: {},
  handler: async (ctx): Promise<string | null> => (await settingsRow(ctx))?.aiModel ?? null,
});

/** What the "Coach model" section shows. Holds no key or part of one. `error` is the last list refresh error, if any. */
export const ai = query({
  args: { token: v.string() },
  handler: async (ctx, { token }) => {
    requireToken(token);
    const row = await settingsRow(ctx);
    const { provider, defaultModel } = envInfo(process.env);
    const override = row?.aiModel ?? null;
    return {
      provider,
      defaultModel,
      model: override ?? defaultModel,
      override,
      models: row?.modelList?.models ?? [],
      fetchedAt: row?.modelList?.fetchedAt ?? null,
      error: row?.modelListError ?? null,
    };
  },
});
