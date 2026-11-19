import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { providerFor, runAiJob } from "../lib/ai";
import { matchExerciseJob } from "../model/ai/jobs/matchExercise";
import sources from "../model/data/exerciseSources.json";
import { type SourceExercise, artPrompt, shortlist } from "../model/exerciseArt";
import { musclesFor } from "../model/rules/muscles";

const COMMIT = sources.commit;
const EXERCISES = sources.exercises as SourceExercise[];
const MATCH_BUDGET_MS = 30_000;
const photoUrl = (id: string, n: 0 | 1) => `https://raw.githubusercontent.com/yuhonas/free-exercise-db/${COMMIT}/exercises/${id}/${n}.jpg`;

/** The row of a key, or null. */
export const row = internalQuery({
  args: { key: v.string() },
  handler: async (ctx, { key }) => {
    const r = await ctx.db.query("exerciseArt").withIndex("by_key", (q) => q.eq("key", key)).first();
    return r ? { name: r.name, status: r.status } : null;
  },
});

/** Sets `ready`. Only a pending row is changed. */
export const saveReady = internalMutation({
  args: { key: v.string(), storageId: v.id("_storage"), sourceId: v.optional(v.string()), model: v.optional(v.string()) },
  handler: async (ctx, { key, storageId, sourceId, model }) => {
    const r = await ctx.db.query("exerciseArt").withIndex("by_key", (q) => q.eq("key", key)).first();
    if (!r || r.status !== "pending") return;
    await ctx.db.patch(r._id, { status: "ready", storageId, ...(sourceId ? { sourceId } : {}), ...(model ? { model } : {}), error: undefined, updatedAt: Date.now() });
  },
});

/** Sets `failed` with a short error (max 300). Only a pending row is changed. */
export const saveFailed = internalMutation({
  args: { key: v.string(), error: v.string() },
  handler: async (ctx, { key, error }) => {
    const r = await ctx.db.query("exerciseArt").withIndex("by_key", (q) => q.eq("key", key)).first();
    if (!r || r.status !== "pending") return;
    await ctx.db.patch(r._id, { status: "failed", error: error.slice(0, 300), updatedAt: Date.now() });
  },
});

/** Removes the art of one exercise (the row and the stored image), so the next request makes it again. For the operator. */
export const remove = internalMutation({
  args: { key: v.string() },
  handler: async (ctx, { key }): Promise<boolean> => {
    const r = await ctx.db.query("exerciseArt").withIndex("by_key", (q) => q.eq("key", key)).first();
    if (!r) return false;
    if (r.storageId) await ctx.storage.delete(r.storageId);
    await ctx.db.delete(r._id);
    return true;
  },
});

async function fetchPhoto(id: string, n: 0 | 1): Promise<{ bytes: Uint8Array; mime: string } | null> {
  try {
    const res = await fetch(photoUrl(id, n));
    if (!res.ok) return null;
    return { bytes: new Uint8Array(await res.arrayBuffer()), mime: "image/jpeg" };
  } catch {
    return null;
  }
}

/**
 * Makes the art of one exercise: shortlist from the public list, match_exercise (skipped on an empty shortlist), the two public photos
 * when matched (a failed photo fetch means: no photos), the image call, store the PNG, set `ready`. Any error sets `failed`. Never throws.
 * Only the exercise name and the public photos go to the provider.
 */
export const make = internalAction({
  args: { key: v.string() },
  handler: async (ctx, { key }): Promise<void> => {
    try {
      const art = await ctx.runQuery(internal.jobs.exerciseArt.row, { key });
      if (!art || art.status !== "pending") return;
      const fail = async (why: string): Promise<void> => {
        await ctx.runMutation(internal.jobs.exerciseArt.saveFailed, { key, error: why });
      };
      try {
        const provider = await providerFor(ctx);
        if (!provider?.image) return await fail("the AI provider cannot draw images");
        const list = shortlist(art.name, EXERCISES);
        // The match job runs also with an empty shortlist: its one-sentence description of the movement guides a drawing made without photos.
        const matched = (await runAiJob(ctx, matchExerciseJob, { exercise: art.name, candidates: list.map((e) => ({ id: e.id, name: e.name, equipment: e.equipment })) }, { timeoutMs: MATCH_BUDGET_MS })).value;
        const matchId = matched.id;
        const match = list.find((e) => e.id === matchId);
        const photos: { bytes: Uint8Array; mime: string }[] = [];
        if (match) {
          const [a, b] = await Promise.all([fetchPhoto(match.id, 0), fetchPhoto(match.id, 1)]);
          if (a && b) photos.push(a, b);
        }
        const muscles = match ? match.muscles : musclesFor(art.name).primary.map((m) => m.replace(/_/g, " "));
        const bytes = await provider.image(artPrompt({ name: art.name, muscles, hasPhotos: photos.length > 0, ...(matched.movement ? { movement: matched.movement } : {}) }), photos);
        const storageId = await ctx.storage.store(new Blob([bytes as BlobPart], { type: "image/png" }));
        await ctx.runMutation(internal.jobs.exerciseArt.saveReady, { key, storageId, ...(match ? { sourceId: match.id } : {}), ...(provider.imageModel ? { model: provider.imageModel } : {}) });
      } catch (e) {
        console.error(`[art] failed: ${(e as Error).message.slice(0, 200)}`);
        await fail((e as Error).message || "failed");
      }
    } catch (e) {
      console.error(`[art] failed: ${(e as Error).message.slice(0, 200)}`);
    }
  },
});
