import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "../functions/_generated/api";
import { buildSessionJob } from "../functions/model/ai/jobs/buildSession";
import { assembleCoachContext } from "../functions/model/coachContext";
import { coachPicture } from "../functions/model/ai/jobs/coachPicture";
import { TOKEN, setup, type T } from "./helpers";

const NOW = Date.UTC(2026, 0, 15, 12);
const HOUR = 3_600_000;
let t: T;
beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
  t = setup();
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

async function upload(fileId: string, name = "meal.jpg", mime = "image/jpeg") {
  const storageId = await t.run((c) => c.storage.store(new Blob(["x"], { type: mime })));
  return t.mutation(api.commands.files.register, { token: TOKEN, fileId, storageId, name, mime, size: 1 });
}
const entry = (entryId: string, over: Partial<{ text: string; fileIds: string[]; at: number; createdAt: number }> = {}) => ({
  entryId,
  text: "Lunch: rice and chicken",
  fileIds: [] as string[],
  at: NOW - HOUR,
  createdAt: NOW - HOUR,
  ...over,
});
const save = (e: ReturnType<typeof entry>) => t.mutation(api.commands.entries.save, { token: TOKEN, entry: e });
const recent = (limit?: number) => t.query(api.queries.entries.recent, { token: TOKEN, limit });
const entryRows = () => t.run((c) => c.db.query("entries").collect());
const fileRows = () => t.run((c) => c.db.query("files").collect());

describe("entries", () => {
  it("saves a note and returns the entryId", async () => {
    expect(await save(entry("e1"))).toBe("e1");
    expect(await recent()).toEqual([{ entryId: "e1", text: "Lunch: rice and chicken", at: NOW - HOUR, createdAt: NOW - HOUR, files: [] }]);
  });

  it("is idempotent per entryId and updates in place", async () => {
    await save(entry("e1"));
    await save(entry("e1"));
    expect(await entryRows()).toHaveLength(1);
    await save(entry("e1", { text: "Lunch, no rice" }));
    expect(await entryRows()).toHaveLength(1);
    expect((await recent())[0]!.text).toBe("Lunch, no rice");
  });

  it("accepts a file with no text", async () => {
    await upload("f1");
    await save(entry("e1", { text: "", fileIds: ["f1"] }));
    const [e] = await recent();
    expect(e!.files).toHaveLength(1);
    expect(e!.files[0]).toMatchObject({ fileId: "f1", name: "meal.jpg", mime: "image/jpeg", kind: "image" });
    expect(e!.files[0]!.url).toMatch(/^https?:\/\//);
  });

  it("rejects bad entries and stores nothing", async () => {
    await upload("f1");
    await expect(save(entry("e1", { text: "   " }))).rejects.toThrow(/note or a file/);
    await expect(save(entry("", { text: "x" }))).rejects.toThrow(/entry/);
    await expect(save(entry("e".repeat(101)))).rejects.toThrow(/entry/);
    await expect(save(entry("e1", { text: "x".repeat(2001) }))).rejects.toThrow(/entry/);
    await expect(save(entry("e1", { fileIds: Array.from({ length: 11 }, (_, i) => `f${i}`) }))).rejects.toThrow(/entry/);
    await expect(save(entry("e1", { fileIds: ["f1", "f1"] }))).rejects.toThrow(/twice/);
    await expect(save(entry("e1", { fileIds: ["nope"] }))).rejects.toThrow(/no registered file/);
    await expect(t.mutation(api.commands.entries.save, { token: "bad", entry: entry("e1") })).rejects.toThrow(/unauthorized/);
    expect(await entryRows()).toHaveLength(0);
  });

  it("deletes a file that an update drops", async () => {
    await upload("f1");
    await upload("f2");
    await save(entry("e1", { fileIds: ["f1", "f2"] }));
    const dropped = (await fileRows()).find((f) => f.fileId === "f1")!.storageId;
    await save(entry("e1", { fileIds: ["f2"] }));
    expect((await fileRows()).map((f) => f.fileId)).toEqual(["f2"]);
    expect(await t.run((c) => c.storage.get(dropped))).toBeNull();
  });

  it("remove only marks the entry (files stay, see softDelete.test.ts) and says false when unknown or marked", async () => {
    await upload("f1");
    await save(entry("e1", { fileIds: ["f1"] }));
    expect(await t.mutation(api.commands.entries.remove, { token: TOKEN, entryId: "e1" })).toBe(true);
    expect(await recent()).toHaveLength(0);
    expect(await entryRows()).toHaveLength(1);
    expect(await fileRows()).toHaveLength(1);
    expect(await t.mutation(api.commands.entries.remove, { token: TOKEN, entryId: "e1" })).toBe(false);
    expect(await t.mutation(api.commands.entries.remove, { token: TOKEN, entryId: "nope" })).toBe(false);
  });

  it("lists newest first by `at`, with a limit", async () => {
    await save(entry("old", { at: NOW - 3 * HOUR }));
    await save(entry("new", { at: NOW - HOUR }));
    await save(entry("mid", { at: NOW - 2 * HOUR }));
    expect((await recent()).map((e) => e.entryId)).toEqual(["new", "mid", "old"]);
    expect((await recent(2)).map((e) => e.entryId)).toEqual(["new", "mid"]);
  });

  it("leaves a missing file out of the list", async () => {
    await upload("f1");
    await upload("f2");
    await save(entry("e1", { fileIds: ["f1", "f2"] }));
    await t.mutation(api.commands.files.remove, { token: TOKEN, fileId: "f1" });
    expect((await recent())[0]!.files.map((f) => f.fileId)).toEqual(["f2"]);
  });
});

describe("coach picture", () => {
  it("holds logEntriesFromTheUser with date, time and the number of attachments", async () => {
    const e = { id: "e1", text: "Lunch", fileIds: ["a", "b"], at: NOW - HOUR, createdAt: NOW - HOUR };
    const p = coachPicture([], [], [], [], [e], NOW);
    expect(p.logEntriesFromTheUser).toEqual([{ date: "2026-01-15", time: "11:00", text: "Lunch", attachments: 2 }]);
    expect(coachPicture([], [], [], [], [], NOW).logEntriesFromTheUser).toEqual([]);
  });

  it("reads the last 7 days, oldest first, at most 20, and the images of the last 24 hours, at most 4", async () => {
    for (let i = 0; i < 6; i++) await upload(`img${i}`);
    for (let i = 0; i < 24; i++) await save(entry(`n${i}`, { at: NOW - (i + 1) * HOUR }));
    await save(entry("img", { at: NOW - 30 * 60_000, fileIds: ["img0", "img1", "img2"] }));
    await save(entry("img2", { at: NOW - 40 * 60_000, fileIds: ["img3", "img4", "img5"] }));
    await save(entry("old", { at: NOW - 8 * 24 * HOUR }));
    const chat = await t.run(async (ctx) => {
      const { coachEntries, entryImageFiles } = await import("../functions/lib/entriesDb");
      return { entries: await coachEntries(ctx, NOW), images: await entryImageFiles(ctx, NOW) };
    });
    expect(chat.entries).toHaveLength(20);
    expect(chat.entries.some((e) => e.id === "old")).toBe(false);
    const times = chat.entries.map((e) => e.at);
    expect(times).toEqual([...times].sort((a, b) => a - b));
    expect(chat.images.map((f) => f.fileId)).toEqual(["img0", "img1", "img2", "img3"]);
  });
});

describe("coach prompts", () => {
  const e = { id: "e1", text: "Lunch", fileIds: ["a"], at: NOW - HOUR, createdAt: NOW - HOUR };
  const image = { mime: "image/jpeg", base64: "eA==" };

  it("build_session carries the entries and the images", () => {
    const p = buildSessionJob.build({ name: "Gym", note: "", picture: coachPicture([], [], [], [], [e], NOW), limits: [], images: [image] });
    expect(p.messages[0]!.content).toContain("logEntriesFromTheUser");
    expect(p.messages[0]!.content).toContain("Lunch");
    expect(p.images).toEqual([image]);
  });

  it("the chat context lists the entries and adds the images only when the provider takes them", () => {
    const data = { otherThreads: [], sessions: [], goals: [], context: [], entries: [e] };
    const on = assembleCoachContext(data, [], true, [image]);
    expect(on.contextBlock).toContain("Log entries from the user");
    expect(on.contextBlock).toContain("Lunch");
    expect(on.sources).toContain("log entries");
    expect(on.images).toEqual([image]);
    const off = assembleCoachContext(data, [], false, [image]);
    expect(off.images).toEqual([]);
    expect(assembleCoachContext({ ...data, entries: [] }, [], true).contextBlock).not.toContain("Log entries");
  });
});
