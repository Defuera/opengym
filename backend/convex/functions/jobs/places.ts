import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { providerFor, runAiJob } from "../lib/ai";
import { loadEntryImages } from "../lib/entriesDb";
import { fileByFileId } from "../lib/files";
import { liveSessionDocs } from "../lib/db";
import { PLACE_QUOTE_MAX, PLACE_TEXT_MAX, placeChangeSource, placeKey } from "../lib/placeFields";
import { allPlaces, createPlace, placeByName, placeByPlaceId, setPlaceText } from "../lib/placesDb";
import { learnPlaceJob } from "../model/ai/jobs/learnPlace";
import { normalizeSession } from "../model/sessionShape";

/** The AI budget for one sentence. Nothing waits for this job. */
const BUDGET_MS = 25_000;
/** Sessions given a place in one run of the seed; a bigger log needs another run (the second run carries on). */
export const SEED_BATCH = 2_000;

/** The note of the place and the names of the other places, or null when the place is gone (the app may be ahead of the server). */
export const learnInput = internalQuery({
  args: { userId: v.string(), placeId: v.string(), fileIds: v.optional(v.array(v.string())) },
  handler: async (ctx, { userId, placeId, fileIds }) => {
    const place = await placeByPlaceId(ctx, userId, placeId);
    if (!place) return null;
    const others = (await allPlaces(ctx, userId)).filter((p) => p.placeId !== placeId).map((p) => p.name);
    // The photos that came with the sentence (at most 6): the user may show the equipment instead of naming it.
    const files = [];
    for (const id of (fileIds ?? []).slice(0, 6)) {
      const f = await fileByFileId(ctx, userId, id);
      if (f && f.kind === "image") files.push({ fileId: f.fileId, storageId: f.storageId, name: f.name, mime: f.mime, size: f.size, kind: f.kind, createdAt: f.createdAt });
    }
    return { place: { name: place.name, equipment: place.text }, otherPlaces: others, files };
  },
});

/**
 * Writes what learn_place found: only when the text differs, and only while the note is still the one the job read
 * (`before`): a newer edit by the user wins. Logs a placeChanges row with the source and the user's sentence. Returns true when it wrote.
 */
export const learnSave = internalMutation({
  args: { userId: v.string(), placeId: v.string(), source: placeChangeSource, sentence: v.string(), before: v.string(), equipment: v.string() },
  handler: async (ctx, { userId, placeId, source, sentence, before, equipment }): Promise<boolean> => {
    const place = await placeByPlaceId(ctx, userId, placeId);
    if (!place) return false;
    return setPlaceText(ctx, userId, place, equipment, source, sentence, before);
  },
});

/**
 * learn_place job (ADR-021): input query -> AI pipeline (one retry, then no change) -> save. Scheduled after a start request is
 * saved (feedback or a note) and after a user message in a thread that has a place. Any error is logged and changes nothing.
 */
export const learn = internalAction({
  args: { userId: v.string(), placeId: v.string(), source: placeChangeSource, sentence: v.string(), fileIds: v.optional(v.array(v.string())) },
  handler: async (ctx, { userId, placeId, source, sentence, fileIds }): Promise<void> => {
    try {
      const quote = sentence.trim().slice(0, PLACE_QUOTE_MAX);
      if (!quote && !fileIds?.length) return;
      const got = await ctx.runQuery(internal.jobs.places.learnInput, { userId, placeId, ...(fileIds ? { fileIds } : {}) });
      if (!got) return;
      const { files, ...i } = got;
      const images = files.length > 0 ? await loadEntryImages(ctx, files, !!(await providerFor(ctx, userId))?.supportsImages) : [];
      if (!quote && images.length === 0) return;
      const r = await runAiJob(ctx, userId, learnPlaceJob, { ...i, sentence: quote, ...(images.length > 0 ? { images } : {}) }, { timeoutMs: images.length > 0 ? 60_000 : BUDGET_MS });
      if (r.path !== "ai" || !r.value.changed) return;
      await ctx.runMutation(internal.jobs.places.learnSave, { userId, placeId, source, sentence: quote || "(photos)", before: i.place.equipment, equipment: r.value.equipment });
    } catch (e) {
      console.error(`[places] learn failed: ${(e as Error).message}`);
    }
  },
});

/** The place a session type goes to in the seed: the activity "Gym" -> Gym; "Home" or a name that starts with the word home -> Home. */
export function seedPlaceName(type: string): "Gym" | "Home" | null {
  const k = placeKey(type);
  if (k === "gym") return "Gym";
  return /^home(\s|$)/.test(k) ? "Home" : null;
}

/**
 * One-off, idempotent (ADR-021). Run by the operator once: `npx convex run jobs/places:seed`.
 * - Makes the place "Gym" with the text of the active context item(s) whose topic is "equipment", then sets those items inactive
 *   (newest first, while the text fits 1500 characters; usually there is one), and logs a placeChanges row with source "seed".
 *   An existing Gym place keeps its text unless it is empty.
 * - Makes the place "Home" with an empty text.
 * - Gives every live session with no place a place: activity "Gym" -> Gym, "Home" (or a name starting with the word home) -> Home;
 *   others stay as they are. A session marked as deleted is not touched. At most SEED_BATCH sessions per run; `remaining` says if more are left.
 * A second run changes nothing. Returns counts.
 */
export const seed = internalMutation({
  args: { userId: v.string() },
  handler: async (ctx, { userId }) => {
    let gym = await placeByName(ctx, userId, "Gym");
    const gymCreated = !gym;
    gym ??= await createPlace(ctx, userId, "Gym");
    let home = await placeByName(ctx, userId, "Home");
    const homeCreated = !home;
    home ??= await createPlace(ctx, userId, "Home");

    let equipmentMoved = 0;
    if (gym.text === "") {
      const items = (await ctx.db.query("context").withIndex("by_user_and_createdAt", (q) => q.eq("userId", userId)).order("desc").collect()).filter((c) => c.active && c.topic.trim().toLowerCase() === "equipment");
      const used: typeof items = [];
      let text = "";
      for (const c of items) {
        const next = text ? `${text}\n${c.text}` : c.text;
        if (next.length > PLACE_TEXT_MAX) break;
        text = next;
        used.push(c);
      }
      if (used.length > 0) {
        await setPlaceText(ctx, userId, gym, text, "seed", "Moved from the context note about equipment");
        for (const c of used) await ctx.db.patch(c._id, { active: false });
        equipmentMoved = used.length;
      }
    }

    const todo = (await liveSessionDocs(ctx, userId, { order: "asc" })).filter((s) => s.placeId === undefined);
    let sessionsGym = 0;
    let sessionsHome = 0;
    for (const s of todo.slice(0, SEED_BATCH)) {
      const target = seedPlaceName(normalizeSession(s).type);
      if (!target) continue;
      await ctx.db.patch(s._id, { placeId: (target === "Gym" ? gym : home).placeId });
      if (target === "Gym") sessionsGym++;
      else sessionsHome++;
    }
    const remaining = todo.slice(SEED_BATCH).filter((s) => seedPlaceName(normalizeSession(s).type) !== null).length;
    return { gymCreated, homeCreated, equipmentMoved, sessionsGym, sessionsHome, remaining };
  },
});
