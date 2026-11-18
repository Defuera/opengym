import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../functions/_generated/api";
import { seedPlaceName } from "../functions/jobs/places";
import { TOKEN, pushSession, setsSession, setup, type T } from "./helpers";

let t: T;
const NOW = Date.UTC(2026, 10, 18, 12);
beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
  t = setup();
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

const saveSession = (s: unknown) => t.mutation(api.commands.sessions.save, { token: TOKEN, session: s as never });
const seed = () => t.mutation(internal.jobs.places.seed, {});
const rows = () => t.run((c) => c.db.query("sessions").collect());
const places = () => t.run((c) => c.db.query("places").collect());
const changes = () => t.run((c) => c.db.query("placeChanges").collect());
const ctxItems = () => t.run((c) => c.db.query("context").collect());
const noteItem = (itemId: string, topic: string, text: string, active = true, createdAt = 1) => t.run((c) => c.db.insert("context", { itemId, text, topic, active, source: "import", createdAt }));
const placeOf = async (sessionId: string) => (await rows()).find((r) => r.sessionId === sessionId)!.placeId;

describe("seedPlaceName", () => {
  it("Gym -> Gym; Home and names that start with the word home -> Home; the rest none", () => {
    expect(seedPlaceName("Gym")).toBe("Gym");
    expect(seedPlaceName(" gym ")).toBe("Gym");
    expect(seedPlaceName("Home")).toBe("Home");
    expect(seedPlaceName("home workout")).toBe("Home");
    expect(seedPlaceName("Homework")).toBeNull();
    expect(seedPlaceName("Run")).toBeNull();
  });
});

describe("jobs/places:seed", () => {
  async function log() {
    await noteItem("c1", "equipment", "Full gym: racks, dumbbells to 40 kg");
    await noteItem("c2", "schedule", "Prefers mornings");
    await saveSession(pushSession("g1", NOW - 5 * 86_400_000)); // Gym
    await saveSession({ ...setsSession("old", NOW - 6 * 86_400_000, "Upper") }); // legacy: flavour in type -> Gym
    await saveSession(setsSession("h1", NOW - 4 * 86_400_000, "Home"));
    await saveSession(setsSession("h2", NOW - 3 * 86_400_000, "home workout"));
    await saveSession({ sessionId: "r1", kind: "activity", type: "Run", startedAt: 1, endedAt: NOW - 2 * 86_400_000, exercises: [], minutes: 30, source: "app" });
    await saveSession({ ...pushSession("g2", NOW - 86_400_000), placeId: "already" }); // keeps its place
    await saveSession(pushSession("gone", NOW - 7 * 86_400_000));
    await t.mutation(api.commands.sessions.remove, { token: TOKEN, sessionId: "gone" });
  }

  it("makes Gym with the equipment note and Home, sets the places, and returns the counts", async () => {
    await log();
    const r = await seed();
    expect(r).toEqual({ gymCreated: true, homeCreated: true, equipmentMoved: 1, sessionsGym: 2, sessionsHome: 2, remaining: 0 });
    const all = await places();
    const gym = all.find((p) => p.name === "Gym")!;
    const home = all.find((p) => p.name === "Home")!;
    expect(gym.text).toBe("Full gym: racks, dumbbells to 40 kg");
    expect(home.text).toBe("");
    expect(await placeOf("g1")).toBe(gym.placeId);
    expect(await placeOf("old")).toBe(gym.placeId);
    expect(await placeOf("h1")).toBe(home.placeId);
    expect(await placeOf("h2")).toBe(home.placeId);
    expect(await placeOf("r1")).toBeUndefined();
    expect(await placeOf("g2")).toBe("already");
    expect(await placeOf("gone")).toBeUndefined(); // marked as deleted: untouched
    expect((await rows()).find((x) => x.sessionId === "gone")!.deletedAt).toBeTypeOf("number");
    const items = await ctxItems();
    expect(items.find((c) => c.itemId === "c1")!.active).toBe(false);
    expect(items.find((c) => c.itemId === "c2")!.active).toBe(true);
    expect(await changes()).toMatchObject([{ placeId: gym.placeId, source: "seed", before: "", after: gym.text }]);
  });

  it("a second run changes nothing", async () => {
    await log();
    await seed();
    const snap = JSON.stringify([await places(), await rows(), await changes(), await ctxItems()]);
    expect(await seed()).toEqual({ gymCreated: false, homeCreated: false, equipmentMoved: 0, sessionsGym: 0, sessionsHome: 0, remaining: 0 });
    expect(JSON.stringify([await places(), await rows(), await changes(), await ctxItems()])).toBe(snap);
  });

  it("works with no equipment note and no sessions: two empty places, nothing logged", async () => {
    expect(await seed()).toMatchObject({ gymCreated: true, homeCreated: true, equipmentMoved: 0, sessionsGym: 0, sessionsHome: 0 });
    expect((await places()).map((p) => [p.name, p.text]).sort()).toEqual([["Gym", ""], ["Home", ""]]);
    expect(await changes()).toHaveLength(0);
  });

  it("an existing Gym place with text keeps it; an inactive equipment note is not used", async () => {
    await t.mutation(api.commands.places.save, { token: TOKEN, placeId: "mine", name: "gym", text: "My text" });
    await noteItem("c1", "equipment", "Old note", true);
    await noteItem("c2", "Equipment", "Inactive", false);
    expect(await seed()).toMatchObject({ gymCreated: false, homeCreated: true, equipmentMoved: 0 });
    expect((await places()).find((p) => p.placeId === "mine")!.text).toBe("My text");
    expect((await ctxItems()).find((c) => c.itemId === "c1")!.active).toBe(true);
  });

  it("more than one equipment note: the newest first while the text fits; those used are set inactive", async () => {
    await noteItem("a", "equipment", "x".repeat(1000), true, 1);
    await noteItem("b", "equipment", "y".repeat(400), true, 2);
    await noteItem("c", "equipment", "z".repeat(400), true, 3);
    expect((await seed()).equipmentMoved).toBe(2); // c and b fit (801 chars); a would make 1802
    const gym = (await places()).find((p) => p.name === "Gym")!;
    expect(gym.text).toBe(`${"z".repeat(400)}\n${"y".repeat(400)}`);
    expect((await ctxItems()).map((c) => [c.itemId, c.active]).sort()).toEqual([["a", true], ["b", false], ["c", false]]);
  });
});
