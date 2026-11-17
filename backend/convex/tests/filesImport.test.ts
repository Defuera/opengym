import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../functions/_generated/api";
import { IMPORT_NEEDS_AI_NOTE } from "../functions/model/ai/jobs/importData";
import { CHUNK_CHARS, MAX_CHUNKS, chunkText, kindOf } from "../functions/model/fileText";
import { TOKEN, setup, settle, type T } from "./helpers";

let t: T;
beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(Date.UTC(2026, 0, 15, 12));
  t = setup();
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

async function upload(fileId: string, name: string, mime: string, content: string | Uint8Array) {
  const storageId = await t.run((c) => c.storage.store(new Blob([content as BlobPart], { type: mime })));
  const size = typeof content === "string" ? content.length : content.length;
  return t.mutation(api.commands.files.register, { token: TOKEN, fileId, storageId, name, mime, size });
}
const start = (importId: string, fileIds: string[]) => t.mutation(api.commands.imports.start, { token: TOKEN, importId, fileIds });
const job = (importId: string) => t.query(api.queries.imports.get, { token: TOKEN, importId });
const count = async (table: "sessions" | "goals" | "context") => (await t.run((c) => c.db.query(table).collect())).length;

describe("files", () => {
  it("generates an upload URL and registers a file with kind, size and a served URL", async () => {
    expect(await t.mutation(api.commands.files.generateUploadUrl, { token: TOKEN })).toMatch(/^https?:\/\//);
    const meta = await upload("f1", "log.csv", "text/csv", "a,b\n1,2");
    expect(meta).toMatchObject({ fileId: "f1", name: "log.csv", mime: "text/csv", size: 7, kind: "text" });
    expect(meta).not.toHaveProperty("storageId");
    const got = await t.query(api.queries.files.get, { token: TOKEN, fileId: "f1" });
    expect(got).toMatchObject({ fileId: "f1", kind: "text", size: 7 });
    expect(got!.url).toMatch(/^https?:\/\//);
    expect(await t.query(api.queries.files.get, { token: TOKEN, fileId: "nope" })).toBeNull();
  });

  it("register is idempotent per fileId", async () => {
    const a = await upload("f1", "a.txt", "text/plain", "x");
    const b = await upload("f1", "a.txt", "text/plain", "x");
    expect(b).toEqual(a);
    expect(await t.run((c) => c.db.query("files").collect())).toHaveLength(1);
  });

  it("remove deletes the row and the blob", async () => {
    await upload("f1", "a.txt", "text/plain", "x");
    const storageId = (await t.run((c) => c.db.query("files").first()))!.storageId;
    expect(await t.mutation(api.commands.files.remove, { token: TOKEN, fileId: "f1" })).toBe(true);
    expect(await t.run((c) => c.storage.get(storageId))).toBeNull();
    expect(await t.mutation(api.commands.files.remove, { token: TOKEN, fileId: "f1" })).toBe(false);
  });

  it("classifies kinds", () => {
    expect(kindOf("a.png", "")).toBe("image");
    expect(kindOf("a", "application/pdf")).toBe("pdf");
    expect(kindOf("a.m4a", "")).toBe("audio");
    expect(kindOf("a.md", "application/octet-stream")).toBe("text");
    expect(kindOf("a.zip", "application/zip")).toBe("other");
  });

  it("rejects a file over 20 MB, by the stored size and by the claimed size", async () => {
    const big = new Uint8Array(20 * 1024 * 1024 + 1);
    const storageId = await t.run((c) => c.storage.store(new Blob([big], { type: "application/pdf" })));
    await expect(t.mutation(api.commands.files.register, { token: TOKEN, fileId: "big", storageId, name: "big.pdf", mime: "application/pdf", size: 1 })).rejects.toThrow(/larger than 20 MB/);
    const small = await t.run((c) => c.storage.store(new Blob(["x"])));
    await expect(t.mutation(api.commands.files.register, { token: TOKEN, fileId: "lie", storageId: small, name: "x.txt", mime: "text/plain", size: 21 * 1024 * 1024 })).rejects.toThrow(/larger than 20 MB/);
    expect(await t.run((c) => c.db.query("files").collect())).toHaveLength(0);
  });

  it("rejects a wrong token", async () => {
    await expect(t.mutation(api.commands.files.generateUploadUrl, { token: "bad" })).rejects.toThrow(/unauthorized/);
    await expect(t.query(api.queries.files.get, { token: "bad", fileId: "f" })).rejects.toThrow(/unauthorized/);
    await expect(t.mutation(api.commands.imports.start, { token: "bad", importId: "i", fileIds: ["f"] })).rejects.toThrow(/unauthorized/);
  });
});

describe("chunking", () => {
  it("splits on line ends and caps at 40 chunks", () => {
    const { chunks, total } = chunkText("line\n".repeat(10_000));
    expect(chunks.length).toBe(total);
    expect(chunks.every((c) => c.length <= CHUNK_CHARS)).toBe(true);
    expect(chunkText("x".repeat(CHUNK_CHARS * (MAX_CHUNKS + 5))).chunks).toHaveLength(MAX_CHUNKS);
  });
});

describe("imports:start (AI import of files, mock provider)", () => {
  it("imports a small text file: running at once, then done with counts and notes; one rebuild", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await upload("f1", "notes.txt", "text/plain", "Push day: bench 6x40, 6x50");
    const j = await start("imp1", ["f1"]);
    expect(j).toMatchObject({ importId: "imp1", status: "running", total: 1, processed: 0, counts: { sessions: 0, goals: 0, context: 0 } });
    await settle(t);
    expect(await job("imp1")).toMatchObject({
      status: "done",
      total: 1,
      processed: 1,
      counts: { sessions: 1, goals: 1, context: 1 },
      notes: [`notes.txt: no date found for some sessions, used the file's upload time (${new Date(Date.UTC(2026, 0, 15, 12)).toISOString()}).`],
    });
    const [s] = await t.query(api.queries.sessions.since, { token: TOKEN, since: 0 });
    expect(s).toMatchObject({ kind: "gym", type: "Gym", focus: "Push", source: "import", importId: "imp1", endedAt: Date.UTC(2026, 0, 15, 12) });
    expect(s!.exercises[0]).toMatchObject({ name: "Bench press", sets: [{ reps: 6, kg: 40, max: false }, { reps: 6, kg: 50, max: false }] });
    expect((await t.query(api.queries.goals.list, { token: TOKEN }))[0]).toMatchObject({ source: "import", importId: "imp1" });
    expect((await t.query(api.queries.context.list, { token: TOKEN }))[0]).toMatchObject({ source: "import", importId: "imp1" });
    expect(await t.run((c) => c.db.query("reviews").collect())).toHaveLength(0); // no per-session review
    expect(await t.run((c) => c.db.query("rebuilds").first())).toMatchObject({ runs: 1 });
  });

  it("a long file becomes several units with live progress; the rebuild is requested once at the end", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await upload("f1", "big.txt", "text/plain", "row of data\n".repeat(2_500)); // 30k chars -> 3 chunks
    await start("imp1", ["f1"]);
    await vi.advanceTimersByTimeAsync(1); // prepare runs, first unit runs
    await t.finishInProgressScheduledFunctions();
    const mid = await job("imp1");
    expect(mid).toMatchObject({ total: 3 });
    expect(mid!.status === "running" ? mid!.processed < 3 : false).toBe(true);
    expect(await t.run((c) => c.db.query("rebuilds").first())).toBeNull(); // no rebuild yet
    await settle(t);
    expect(await job("imp1")).toMatchObject({ status: "done", total: 3, processed: 3, counts: { sessions: 3, goals: 3, context: 3 } });
    expect(await t.run((c) => c.db.query("rebuilds").first())).toMatchObject({ runs: 1 });
  });

  it("notes when a file has more than 40 chunks", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await upload("f1", "huge.txt", "text/plain", "x".repeat(CHUNK_CHARS * 41));
    await start("imp1", ["f1"]);
    await settle(t);
    const j = await job("imp1");
    expect(j).toMatchObject({ status: "done", total: 40, processed: 40 });
    expect(j!.notes).toContain(`huge.txt: only the first 40 of 41 chunks (${CHUNK_CHARS} chars each) were processed.`);
  });

  it("reads an image with the mock provider (a machine screen)", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await upload("p1", "bike.jpg", "image/jpeg", new Uint8Array([1, 2, 3]));
    await start("imp1", ["p1"]);
    await settle(t);
    expect(await job("imp1")).toMatchObject({ status: "done", counts: { sessions: 1, goals: 0, context: 0 } });
    expect((await job("imp1"))!.notes).toContain("bike.jpg: Mock read the machine screen.");
    expect((await t.query(api.queries.sessions.since, { token: TOKEN, since: 0 }))[0]).toMatchObject({ kind: "activity", type: "Cycle", minutes: 30, distanceKm: 12.5 });
  });

  it("files that carry no text finish done with a note and no AI call", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await upload("a1", "voice.m4a", "audio/mp4", "x");
    await upload("z1", "x.zip", "application/zip", "x");
    await start("imp1", ["a1", "z1"]);
    await settle(t);
    expect(await job("imp1")).toMatchObject({ status: "done", total: 0, notes: ["voice.m4a: audio is stored but not transcribed.", "x.zip: unsupported file type, stored only."] });
  });

  it("a PDF that cannot be read gives a note instead of an error", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await upload("d1", "scan.pdf", "application/pdf", "not really a pdf");
    await start("imp1", ["d1"]);
    await settle(t);
    const j = await job("imp1");
    expect(j!.status).toBe("done");
    expect(j!.notes[0]).toMatch(/^scan\.pdf: PDF text extraction is unavailable|^scan\.pdf: PDF has no extractable text/);
  });

  it("with AI_PROVIDER=none nothing is imported and the note says AI is required", async () => {
    await upload("f1", "notes.txt", "text/plain", "Push day");
    await start("imp1", ["f1"]);
    await settle(t);
    expect(await job("imp1")).toMatchObject({ status: "done", total: 1, processed: 1, counts: { sessions: 0, goals: 0, context: 0 }, notes: [`notes.txt: ${IMPORT_NEEDS_AI_NOTE}`] });
    expect(await count("sessions")).toBe(0);
  });

  it("a failing unit ends the job as failed with a note; the other units stop", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await upload("p1", "gone.png", "image/png", new Uint8Array([1]));
    const j = await start("imp1", ["p1"]);
    const storageId = (await t.run((c) => c.db.query("files").first()))!.storageId;
    await t.run((c) => c.storage.delete(storageId)); // the blob vanishes before the unit reads it
    await t.action(internal.jobs.importFiles.unit, { importId: j.importId, fileName: "gone.png", fileCreatedAt: 1, uploadedAt: "x", chunkIndex: 0, chunkCount: 1, image: { storageId, mime: "image/png" } });
    expect(await job("imp1")).toMatchObject({ status: "failed" });
    expect((await job("imp1"))!.notes.at(-1)).toMatch(/^Import failed: gone\.png: the stored file is missing/);
    await settle(t); // prepare finds the blob missing and skips; it must not revive the job
    expect((await job("imp1"))!.status).toBe("failed");
    expect(await t.run((c) => c.db.query("rebuilds").first())).toBeNull();
  });

  it("start is idempotent, checks the files exist, and remove clears the imported items", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await expect(start("imp1", ["missing"])).rejects.toThrow(/file not found/);
    await expect(start("imp1", [])).rejects.toThrow(/at least one/);
    await upload("f1", "notes.txt", "text/plain", "Push day");
    const a = await start("imp1", ["f1"]);
    const b = await start("imp1", ["f1"]);
    expect(b.importId).toBe(a.importId);
    await settle(t);
    expect(await t.run((c) => c.db.query("imports").collect())).toHaveLength(1);
    expect(await count("sessions")).toBe(1);

    expect(await t.mutation(api.commands.imports.remove, { token: TOKEN, importId: "imp1" })).toBe(true);
    expect([await count("sessions"), await count("goals"), await count("context")]).toEqual([0, 0, 0]);
    expect(await job("imp1")).toBeNull();
    await settle(t);
  });

  it("removing a running import stops its units from writing", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    await upload("f1", "big.txt", "text/plain", "row of data\n".repeat(2_500));
    await start("imp1", ["f1"]);
    await vi.advanceTimersByTimeAsync(1);
    await t.finishInProgressScheduledFunctions();
    await t.mutation(api.commands.imports.remove, { token: TOKEN, importId: "imp1" });
    await settle(t);
    expect([await count("sessions"), await count("goals"), await count("context")]).toEqual([0, 0, 0]);
  });
});
