import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalQuery } from "../_generated/server";
import { runAiJob } from "../lib/ai";
import { allContext, allGoals, allSessions } from "../lib/db";
import { coachEntries } from "../lib/entriesDb";
import { activeLimits } from "../lib/limitsDb";
import { buildSessionJob } from "../model/ai/jobs/buildSession";
import { coachPicture } from "../model/ai/jobs/coachPicture";
import { buildInterpretInput } from "../model/ai/jobs/inputs";
import { interpretRequestJob } from "../model/ai/jobs/interpretRequest";

/** Prompt comparison only: builds both inputs, saves nothing. Internal, so only the owner's CLI can run it. */
export const inputs = internalQuery({
  args: { name: v.string(), text: v.string() },
  handler: async (ctx, { name, text }) => {
    const [sessions, goals, context, limits] = [await allSessions(ctx), await allGoals(ctx), await allContext(ctx), await activeLimits(ctx)];
    const now = Date.now();
    const ordered = [...goals].sort((a, b) => a.createdAt - b.createdAt);
    return {
      old: buildInterpretInput(text, sessions, ordered, context, limits, now, name),
      next: { name, note: text, picture: coachPicture(sessions, ordered, context, limits, await coachEntries(ctx, now), now), limits },
    };
  },
});

export const run = internalAction({
  args: { name: v.string(), text: v.string(), variant: v.union(v.literal("old"), v.literal("new")) },
  handler: async (ctx, { name, text, variant }): Promise<unknown> => {
    const i = await ctx.runQuery(internal.jobs.promptLab.inputs, { name, text });
    const t = Date.now();
    const r = variant === "old" ? await runAiJob(ctx, interpretRequestJob, i.old, { timeoutMs: 60_000 }) : await runAiJob(ctx, buildSessionJob, i.next, { timeoutMs: 60_000 });
    return { path: r.path, ms: Date.now() - t, value: r.value };
  },
});
