import { readFileSync } from "node:fs";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "../functions/_generated/api";
import { EXERCISE_ART_DAILY_MAX } from "../functions/lib/constants";
import sources from "../functions/model/data/exerciseSources.json";
import { type SourceExercise, artKey, artPrompt, shortlist } from "../functions/model/exerciseArt";
import { TOKEN, setup, settle, stubOpenAi, type T } from "./helpers";

const EX = sources.exercises as SourceExercise[];
const DAY = 86_400_000;
let t: T;
const NOW = Date.UTC(2026, 10, 19, 12);
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

const request = (names: string[]) => t.mutation(api.commands.exerciseArt.request, { token: TOKEN, names });
const get = (names: string[]) => t.query(api.queries.exerciseArt.get, { token: TOKEN, names });
const rows = () => t.run((c) => c.db.query("exerciseArt").collect());

describe("artKey and shortlist", () => {
  it("makes the key from trim, lower case and one space", () => {
    expect(artKey("  Leg   PRESS\t ")).toBe("leg press");
  });

  it("puts an exact normalised match first and strips a plural s", () => {
    const list = shortlist("Barbell Curls", EX);
    expect(list.length).toBeGreaterThan(1);
    expect(list.length).toBeLessThanOrEqual(12);
    expect(list[0]!.name.toLowerCase()).toBe("barbell curl");
  });

  it("returns [] when no word overlaps", () => {
    expect(shortlist("qqqq zzzz", EX)).toEqual([]);
  });

  it("honours n", () => {
    expect(shortlist("press", EX, 3)).toHaveLength(3);
  });
});

describe("artPrompt", () => {
  it("holds the name and the muscles, with and without photos", () => {
    const a = artPrompt({ name: "Leg press", muscles: ["quadriceps", "glutes"], hasPhotos: true });
    expect(a).toContain('the exercise "Leg press"');
    expect(a).toContain("the working muscles (quadriceps, glutes) filled solid royal blue #2448E8");
    expect(a).toContain("Redraw the two reference photos");
    const b = artPrompt({ name: "Leg press", muscles: [], hasPhotos: false });
    expect(b).toContain("Draw ONE flat illustration");
    expect(b).toContain("the working muscles filled solid royal blue #2448E8");
  });
});

describe("commands/exerciseArt:request", () => {
  it("is idempotent and starts one row per key", async () => {
    await request(["Leg press", " leg  PRESS "]);
    await request(["Leg press"]);
    expect(await rows()).toHaveLength(1);
    expect(await rows()).toMatchObject([{ key: "leg press", name: "Leg press", status: "pending" }]);
    expect(await get(["Leg press", "Squat"])).toEqual([{ name: "Leg press", status: "pending", url: null }, { name: "Squat", status: "none", url: null }]);
    await settle(t);
  });

  it("validates the names", async () => {
    await expect(request([])).rejects.toThrow(/1 to 12/);
    await expect(request(Array.from({ length: 13 }, (_, i) => `e${i}`))).rejects.toThrow(/1 to 12/);
    await expect(request(["  "])).rejects.toThrow(/1 to 80/);
    await expect(request(["x".repeat(81)])).rejects.toThrow(/1 to 80/);
    await expect(t.mutation(api.commands.exerciseArt.request, { token: "bad", names: ["a"] })).rejects.toThrow(/unauthorized/);
    expect(await rows()).toHaveLength(0);
    await expect(get(Array.from({ length: 31 }, (_, i) => `e${i}`))).rejects.toThrow(/30/);
  });

  it("respects the daily cap and skips the rest silently", async () => {
    for (let i = 0; i < 4; i++) await request(Array.from({ length: 12 }, (_, j) => `exercise ${i * 12 + j}`));
    expect(await rows()).toHaveLength(EXERCISE_ART_DAILY_MAX);
    await settle(t);
  });

  it("tries an old failed row again, not a young one", async () => {
    await request(["Squat"]);
    await settle(t); // AI is off: the row fails
    expect(await rows()).toMatchObject([{ status: "failed" }]);
    await request(["Squat"]);
    expect(await rows()).toMatchObject([{ status: "failed" }]);
    vi.setSystemTime(NOW + DAY + 1000);
    await request(["Squat"]);
    expect(await rows()).toMatchObject([{ status: "pending" }]);
    expect((await rows())[0]!.error).toBeUndefined();
    await settle(t);
  });
});

/** Stubs fetch for the OpenAI chat (match_exercise), the photos and the image calls. */
const fixture = (name: string) => new Uint8Array(readFileSync(new URL(`./fixtures/${name}`, import.meta.url)));
const b64 = (bytes: Uint8Array) => Buffer.from(bytes).toString("base64");

function stubAll(opts: { match: (candidates: { id: string }[]) => string | null; photos?: boolean; image?: "ok" | "error"; pictures?: Uint8Array[] }) {
  let drawn = 0;
  vi.stubEnv("AI_PROVIDER", "openai");
  vi.stubEnv("OPENAI_API_KEY", "test-key");
  vi.stubEnv("OPENAI_MODEL", "test-model");
  const log: { url: string; method: string; body?: unknown }[] = [];
  vi.stubGlobal("fetch", async (url: string, init?: RequestInit) => {
    const u = String(url);
    if (u.includes("raw.githubusercontent.com")) {
      log.push({ url: u, method: "GET" });
      return opts.photos === false ? new Response("nope", { status: 404 }) : new Response(new Uint8Array([1, 2, 3]), { status: 200 });
    }
    if (u.endsWith("/v1/chat/completions")) {
      const body = JSON.parse(init!.body as string);
      const user: string = body.messages[body.messages.length - 1].content;
      const input = JSON.parse(user.slice(user.indexOf("INPUT_JSON:\n") + 12));
      log.push({ url: u, method: "POST", body: input });
      return new Response(JSON.stringify({ choices: [{ message: { content: JSON.stringify({ id: opts.match(input.candidates) }) } }] }), { status: 200 });
    }
    log.push({ url: u, method: "POST", body: init!.body });
    if (opts.image === "error") return new Response("boom", { status: 500 });
    const picture = opts.pictures?.[Math.min(drawn++, opts.pictures.length - 1)];
    return new Response(JSON.stringify({ data: [{ b64_json: picture ? b64(picture) : btoa("PNGBYTES") }] }), { status: 200 });
  });
  return log;
}

describe("jobs/exerciseArt:make", () => {
  it("matches, fetches two photos, calls the image edit and ends ready with a url", async () => {
    const log = stubAll({ match: (c) => c[0]!.id });
    await request(["Barbell Curl"]);
    await settle(t);
    const [row] = await rows();
    expect(row).toMatchObject({ status: "ready", sourceId: "Barbell_Curl", model: "gpt-image-2" });
    expect(log.filter((l) => l.url.includes("raw.githubusercontent.com")).map((l) => l.url.slice(-18))).toEqual(["Barbell_Curl/0.jpg", "Barbell_Curl/1.jpg"]);
    const img = log.find((l) => l.url.endsWith("/v1/images/edits"))!;
    expect(img.body).toBeInstanceOf(FormData);
    const form = img.body as FormData;
    expect(form.get("size")).toBe("1536x1024");
    expect(form.get("quality")).toBe("medium");
    expect(form.getAll("image[]")).toHaveLength(2);
    expect(String(form.get("prompt"))).toContain("Redraw the two reference photos");
    const [item] = await get(["Barbell Curl"]);
    expect(item).toMatchObject({ status: "ready" });
    expect(item!.url).toEqual(expect.any(String));
    const stored = await t.run(async (c) => {
      const blob = await c.storage.get(row!.storageId!);
      return { type: blob!.type, text: new TextDecoder().decode(await blob!.arrayBuffer()) };
    });
    expect(stored).toEqual({ type: "image/png", text: "PNGBYTES" });
  });

  it("goes to generations without photos when nothing matches, and for a failed photo fetch", async () => {
    const log = stubAll({ match: () => null });
    await request(["Barbell Curl"]);
    await settle(t);
    expect(await rows()).toMatchObject([{ status: "ready" }]);
    expect((await rows())[0]!.sourceId).toBeUndefined();
    expect(log.some((l) => l.url.endsWith("/v1/images/generations"))).toBe(true);
    expect(log.some((l) => l.url.includes("raw.githubusercontent.com"))).toBe(false);
    const gen = JSON.parse(String(log.find((l) => l.url.endsWith("/v1/images/generations"))!.body));
    expect(gen).toMatchObject({ model: "gpt-image-2", size: "1536x1024", quality: "medium" });
    expect(gen.prompt).toContain("Draw ONE flat illustration");

    const log2 = stubAll({ match: (c) => c[0]!.id, photos: false });
    await request(["Barbell Curl "]); // same key: stays ready, nothing runs
    await request(["Hammer Curl"]);
    await settle(t);
    expect(await rows()).toHaveLength(2);
    expect(log2.some((l) => l.url.endsWith("/v1/images/generations"))).toBe(true);
  });

  it("asks for the movement also with an empty shortlist, and draws without photos", async () => {
    const log = stubAll({ match: () => null });
    await request(["qqqq zzzz"]);
    await settle(t);
    expect(log.some((l) => l.url.endsWith("/v1/chat/completions"))).toBe(true);
    expect(log.some((l) => l.url.endsWith("/v1/images/generations"))).toBe(true);
    expect(await rows()).toMatchObject([{ status: "ready" }]);
  });

  it("a provider error ends failed with a short error", async () => {
    stubAll({ match: () => null, image: "error" });
    await request(["Barbell Curl"]);
    await settle(t);
    const [row] = await rows();
    expect(row).toMatchObject({ status: "failed" });
    expect(row!.error!.length).toBeLessThanOrEqual(300);
    expect(await get(["Barbell Curl"])).toEqual([{ name: "Barbell Curl", status: "failed", url: null }]);
  });

  it("a provider with no image method ends failed", async () => {
    vi.stubEnv("AI_PROVIDER", "deepseek");
    vi.stubEnv("DEEPSEEK_API_KEY", "k");
    vi.stubEnv("DEEPSEEK_MODEL", "m");
    await request(["Barbell Curl"]);
    await settle(t);
    expect(await rows()).toMatchObject([{ status: "failed" }]);
  });

  it("the mock provider draws and matches by name", async () => {
    vi.stubEnv("AI_PROVIDER", "mock");
    vi.stubGlobal("fetch", async () => new Response("x", { status: 404 }));
    await request(["Barbell Curl"]);
    await settle(t);
    expect(await rows()).toMatchObject([{ status: "ready", model: "mock-image" }]);
  });
});

describe("the check that the figure stays in place", () => {
  const draws = (log: { url: string }[]) => log.filter((l) => l.url.includes("/v1/images/")).length;
  const storedSize = async () => {
    const [row] = await rows();
    return t.run(async (c) => (await c.storage.get(row!.storageId!))!.size);
  };

  it("draws again when the figure jumps, and keeps the steady picture", async () => {
    const steady = fixture("art-steady.png");
    const log = stubAll({ match: () => null, pictures: [fixture("art-jump.png"), steady] });
    await request(["One-Leg Stand"]);
    await settle(t);
    expect(draws(log)).toBe(2);
    expect(await rows()).toMatchObject([{ status: "ready", tries: 2, shift: { dx: 0, dy: 0 } }]);
    expect(await storedSize()).toBe(steady.length);
  });

  it("stops after three pictures and keeps the steadiest", async () => {
    const small = fixture("art-small-jump.png");
    const log = stubAll({ match: () => null, pictures: [fixture("art-jump.png"), small, fixture("art-jump.png")] });
    await request(["One-Leg Stand"]);
    await settle(t);
    expect(draws(log)).toBe(3);
    const [row] = await rows();
    expect(row).toMatchObject({ status: "ready", tries: 3 });
    expect(row!.shift!.dx).toBeLessThan(0.08);
    expect(await storedSize()).toBe(small.length);
  });

  it("draws once when the figure is steady", async () => {
    const log = stubAll({ match: () => null, pictures: [fixture("art-steady.png")] });
    await request(["One-Leg Stand"]);
    await settle(t);
    expect(draws(log)).toBe(1);
    expect(await rows()).toMatchObject([{ status: "ready", tries: 1 }]);
  });
});

describe("saving a proposal", () => {
  it("requests art for the exercises of the plan", async () => {
    stubOpenAi((job) => (job === "build_session" ? JSON.stringify({ kind: "gym", type: "Home", plan: { rationale: "r", exercises: [{ name: "Push-up", sets: [{ reps: 10, kg: 0, max: false }] }, { name: "Goblet squat", sets: [{ reps: 10, kg: 8, max: false }] }] } }) : "{}"));
    await t.mutation(api.commands.start.request, { token: TOKEN, requestId: "r1", name: "Home" });
    await settle(t);
    expect((await rows()).map((r) => r.key).sort()).toEqual(["goblet squat", "push-up"]);
  });
});
