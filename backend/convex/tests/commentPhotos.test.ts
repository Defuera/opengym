import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../functions/_generated/api";
import { commentInViewImageFiles } from "../functions/lib/entriesDb";
import { DELETE_AFTER_MS } from "../functions/lib/constants";
import { exerciseForPrompt } from "../functions/model/coachTurnInput";
import { hasDone, replaceOne, type OpenExercise } from "../functions/model/openSession";
import { pushSession, setup, settle, TOKEN, type T } from "./helpers";
import { TOKEN_B, USER_A, USER_B, setupTwo } from "./multiUser";

/** ADR-043: the comment on an exercise holds photos. `commentFileIds` are ids of the person's own files. */
const NOW = 2_000_000_000_000;
const photoEx = (name: string, ids: string[]): OpenExercise => ({ id: `id-${name}`, name, sets: [{ reps: 10, kg: 0, done: false }], fresh: false, carry: false, commentFileIds: ids });
const open = (exercises: OpenExercise[]) => ({ id: "os1", kind: "gym" as const, type: "Gym", startedAt: 1000, source: "app", exercises });

async function addFile(t: T, token: string, fileId: string) {
  const storageId = await t.run((c) => c.storage.store(new Blob(["x"], { type: "image/jpeg" })));
  await t.mutation(api.commands.files.register, { token, fileId, storageId, name: `${fileId}.jpg`, mime: "image/jpeg", size: 1 });
  return storageId;
}

describe("comment photos", () => {
  let t: T;
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(NOW);
    t = setup();
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllEnvs();
  });

  it("the open session stores commentFileIds and gives them back", async () => {
    await t.mutation(api.commands.openSession.put, { token: TOKEN, session: open([{ ...photoEx("Bike", ["f1", "f2"]), comment: "level 9" }]) });
    const r = await t.query(api.queries.openSession.get, { token: TOKEN });
    expect(r.session!.exercises[0]).toMatchObject({ comment: "level 9", commentFileIds: ["f1", "f2"] });
  });

  it("a comment of photos only counts as the person's work, and the coach sees how many", () => {
    const e = photoEx("Bike", ["f1"]);
    expect(hasDone(e)).toBe(true);
    expect(hasDone(photoEx("Row", []))).toBe(false);
    expect(exerciseForPrompt(e)).toMatchObject({ commentPhotos: 1, personsWork: true });
    expect(exerciseForPrompt(photoEx("Row", []))).not.toHaveProperty("commentPhotos");
  });

  it("is kept when the session is finished (sessions:save), in both exercise shapes", async () => {
    const s = pushSession("c1", NOW - 3_600_000);
    (s.exercises[1] as { commentFileIds?: string[] }).commentFileIds = ["f1", "f2"];
    const timeEx = { name: "Bike", measure: "time" as const, sets: [{ minutes: 20 }], comment: "hard", commentFileIds: ["f3"] };
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: { ...s, exercises: [...s.exercises, timeEx] } });
    const [stored] = await t.query(api.queries.sessions.recent, { token: TOKEN });
    expect(stored!.exercises[1]).toMatchObject({ name: "Dips", commentFileIds: ["f1", "f2"] });
    expect(stored!.exercises[0]).not.toHaveProperty("commentFileIds");
    expect(stored!.exercises[2]).toMatchObject({ name: "Bike", commentFileIds: ["f3"] });
    await settle(t);
  });

  it("rejects more than 10 photos on one comment", async () => {
    const s = pushSession("many", 2_000_000);
    (s.exercises[0] as { commentFileIds?: string[] }).commentFileIds = Array.from({ length: 11 }, (_, i) => `f${i}`);
    await expect(t.mutation(api.commands.sessions.save, { token: TOKEN, session: s })).rejects.toThrow();
  });

  it("the coach replace keeps the photos with the comment", () => {
    const old = { ...photoEx("Bike", ["f1"]), comment: "level 9" };
    const out = replaceOne([old], old.id, { name: "Bike", sets: [{ reps: 12, kg: 10 }] }, "new");
    expect(out.ok).toBe(true);
    if (out.ok) expect(out.exercises[0]).toMatchObject({ id: old.id, comment: "level 9", commentFileIds: ["f1"] });
    // photos only (no text): the exercise is locked the same way
    const only = photoEx("Row", ["f2"]);
    const renamed = replaceOne([only], only.id, { name: "Other", sets: [{ reps: 12, kg: 10 }] }, "new");
    expect(renamed.ok).toBe(false);
  });

  it("an outside plan keeps an exercise whose comment is photos only", async () => {
    await t.mutation(api.commands.openSession.put, { token: TOKEN, session: open([photoEx("Bike", ["f1"]), photoEx("Walk", [])]) });
    await t.mutation(internal.jobs.openSession.replacePlan, { userId: USER_A, id: "os1", by: "coach", exercises: [{ name: "Squat", sets: [{ reps: 10, kg: 0 }] }] });
    const r = await t.query(api.queries.openSession.get, { token: TOKEN });
    expect(r.session!.exercises.map((e) => e.name)).toEqual(["Bike", "Squat"]);
    expect(r.session!.exercises[0]!.commentFileIds).toEqual(["f1"]);
  });

  it("the coach gets the image files of the comment, from the person's own files only", async () => {
    await addFile(t, TOKEN, "f1");
    const own = await t.run((c) => commentInViewImageFiles(c, USER_A, ["f1", "missing"]));
    expect(own.map((f) => f.fileId)).toEqual(["f1"]);
    expect(await t.run((c) => commentInViewImageFiles(c, USER_A, undefined))).toEqual([]);
  });

  it("the photos go when the marked session is erased", async () => {
    const storageId = await addFile(t, TOKEN, "f1");
    const s = pushSession("gone", NOW - 3_600_000);
    (s.exercises[1] as { commentFileIds?: string[] }).commentFileIds = ["f1"];
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: s });
    await t.mutation(api.commands.sessions.remove, { token: TOKEN, sessionId: "gone" });
    vi.setSystemTime(NOW + DELETE_AFTER_MS + 1000);
    await t.mutation(internal.jobs.purge.run, {});
    expect(await t.run(async (c) => (await c.storage.get(storageId)) !== null)).toBe(false);
    expect(await t.run((c) => c.db.query("files").collect())).toHaveLength(0);
    await settle(t);
  });
});

describe("comment photos, two users", () => {
  let t: T;
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(NOW);
    t = setupTwo();
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllEnvs();
  });

  it("the same file id of another user shows nothing, and each user reads only own photos", async () => {
    await addFile(t, TOKEN, "same");
    // user B names user A's file id on a comment: B's lookups find nothing, and B's open session holds only B's own list
    await t.mutation(api.commands.openSession.put, { token: TOKEN_B, session: open([photoEx("Bike", ["same"])]) });
    expect(await t.query(api.queries.files.get, { token: TOKEN_B, fileId: "same" })).toBeNull();
    expect(await t.run((c) => commentInViewImageFiles(c, USER_B, ["same"]))).toEqual([]);
    expect((await t.query(api.queries.files.get, { token: TOKEN, fileId: "same" }))?.fileId).toBe("same");
    // user A's open session is untouched by B's write
    expect((await t.query(api.queries.openSession.get, { token: TOKEN })).session).toBeNull();
    const b = await t.query(api.queries.openSession.get, { token: TOKEN_B });
    expect(b.session!.exercises[0]!.commentFileIds).toEqual(["same"]);
  });
});
