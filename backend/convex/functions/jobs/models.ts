import { v } from "convex/values";
import { internalAction, internalMutation } from "../_generated/server";
import { internal } from "../_generated/api";
import { patchSettings } from "../lib/settingsDb";
import { ConfigError, createProviderFromEnv } from "../model/ai/factory";

/** A short error text for the app. Never the raw provider message: it may echo part of a key. */
export function listError(e: unknown): string {
  const m = (e as Error)?.message ?? "";
  const status = m.match(/^HTTP (\d{3})/)?.[1];
  if (status) return `The provider answered HTTP ${status}.`;
  if (/timed out/.test(m)) return "The provider did not answer in time.";
  if (e instanceof ConfigError) return "The AI provider is not set up.";
  return "Could not reach the provider.";
}

/** Store a fresh list, or only an error text (the old list stays). */
export const saveModels = internalMutation({
  args: { models: v.optional(v.array(v.string())), error: v.optional(v.string()) },
  handler: async (ctx, { models, error }) => {
    if (models) await patchSettings(ctx, { modelList: { models, fetchedAt: Date.now() }, modelListError: undefined });
    else await patchSettings(ctx, { modelListError: error ?? "Could not load the list." });
  },
});

/** Asks the current provider (env key, current base URL) for its text models. Scheduled by commands/settings:refreshModels. */
export const refresh = internalAction({
  args: {},
  handler: async (ctx): Promise<void> => {
    try {
      const provider = createProviderFromEnv(process.env);
      const models = provider ? await provider.listModels() : [];
      await ctx.runMutation(internal.jobs.models.saveModels, { models });
    } catch (e) {
      await ctx.runMutation(internal.jobs.models.saveModels, { error: listError(e) });
    }
  },
});
