import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api, internal } from "../functions/_generated/api";
import { buildSessionJob } from "../functions/model/ai/jobs/buildSession";
import { coachPicture } from "../functions/model/ai/jobs/coachPicture";
import { learnPlaceJob } from "../functions/model/ai/jobs/learnPlace";
import { StartProposalSchema } from "../functions/model/schema";
import { TOKEN, setsSession, pushSession, setup, settle, stubOpenAi, type T } from "./helpers";

let t: T;
const NOW = Date.UTC(2026, 10, 18, 12);
const DAY = 86_400_000;
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

const plan = { rationale: "r", exercises: [{ name: "Goblet squat", sets: [{ reps: 10, kg: 10, max: false }] }] };
const place = (placeId: string, name: string, text = "") => t.mutation(api.commands.places.save, { token: TOKEN, placeId, name, text });
const places = () => t.run((c) => c.db.query("places").collect());
const changes = () => t.run((c) => c.db.query("placeChanges").collect());
const saveSession = (s: unknown) => t.mutation(api.commands.sessions.save, { token: TOKEN, session: s as never });
const start = (requestId: string, name?: string, text?: string) => t.mutation(api.commands.start.request, { token: TOKEN, requestId, ...(name ? { name } : {}), ...(text ? { text } : {}) });
const again = (requestId: string, previousRequestId: string, feedback: string) => t.mutation(api.commands.start.request, { token: TOKEN, requestId, previousRequestId, feedback });
const get = (requestId: string) => t.query(api.queries.start.request, { token: TOKEN, requestId });
const builds = (calls: { job: string; input: any }[]) => calls.filter((c) => c.job === "build_session"); // eslint-disable-line @typescript-eslint/no-explicit-any
const learns = (calls: { job: string; input: any }[]) => calls.filter((c) => c.job === "learn_place"); // eslint-disable-line @typescript-eslint/no-explicit-any
/** The coach answers a start request with `placeName` (or no place) and never changes a note. */
const coach = (placeName?: string, learn: object = { changed: false, equipment: "" }) => (job: string) =>
  job === "build_session" ? JSON.stringify({ kind: "gym", type: "Home", plan, ...(placeName ? { place: placeName } : {}) }) : job === "learn_place" ? JSON.stringify(learn) : "{}";

describe("a rebuild keeps the place (ADR-035, trace of 24 Nov)", () => {
  it("equipment feedback does not move the proposal from Gym to Home, and the model sees currentPlace", async () => {
    await place("p-home", "Home", "Balance board");
    await place("p-gym", "Gym");
    stubOpenAi(coach("Gym"));
    await start("r1", "Gym", "legs");
    await settle(t);
    expect((await get("r1"))!.proposal!.place).toMatchObject({ placeId: "p-gym" });
    const calls = stubOpenAi(coach("Home"));
    await again("r2", "r1", "I do have balance board");
    await settle(t);
    expect(builds(calls)[0]!.input.currentPlace).toBe("Gym");
    expect((await get("r2"))!.proposal!.place).toMatchObject({ placeId: "p-gym", name: "Gym" });
    stubOpenAi(coach("Home"));
    await again("r3", "r2", "I am at home today");
    await settle(t);
    expect((await get("r3"))!.proposal!.place).toMatchObject({ placeId: "p-home" });
  });
});

describe("build_session and places", () => {
  const picture = coachPicture([], [], [], [], [], 0);
  const input = { name: "Home", note: "", picture, limits: [] };

  it("the input carries placesTheCoachKnows when given, and the role has the two sentences", () => {
    const given = [{ name: "Home", equipment: "Dumbbells", lastUsedForThisActivity: true }, { name: "Gym", equipment: "", lastUsedForThisActivity: false }];
    const p = buildSessionJob.build({ ...input, placesTheCoachKnows: given });
    expect(JSON.parse(p.messages[0]!.content.split("INPUT_JSON:\n")[1]!).placesTheCoachKnows).toEqual(given);
    expect(p.system.match(/placesTheCoachKnows/g)).toHaveLength(2); // one in the role, one in the output shape note
    expect(p.system).toContain("plan with the equipment that place names");
    expect(p.system).toContain("never a full list");
    expect(p.system).toContain("Balance board if your gym has one; otherwise tandem stand");
    expect(p.system).toContain("empty equipment text is unknown");
    expect(buildSessionJob.build(input).messages[0]!.content).not.toContain("placesTheCoachKnows");
  });

  it("the output may hold a place of at most 30 characters; it is optional", () => {
    const base = { kind: "gym", type: "Home", plan };
    expect(StartProposalSchema.safeParse(base).success).toBe(true);
    expect(StartProposalSchema.safeParse({ ...base, place: "Hotel gym" }).success).toBe(true);
    expect(StartProposalSchema.safeParse({ ...base, place: "x".repeat(31) }).success).toBe(false);
    expect(StartProposalSchema.safeParse({ ...base, place: "" }).success).toBe(false);
  });

  it("the fallback gives no place", () => {
    expect(buildSessionJob.fallback(input)).not.toHaveProperty("place");
  });
});

describe("the place of a proposal", () => {
  beforeEach(async () => {
    await place("p-gym", "Gym", "Rack, barbell, machines");
    await place("p-home", "Home", "Two dumbbells");
  });

  it("sends every place to the coach, with the one last used for this activity marked", async () => {
    await saveSession({ ...setsSession("h1", NOW - 3 * DAY, "Home"), placeId: "p-home" });
    await saveSession({ ...pushSession("g1", NOW - DAY), placeId: "p-gym" });
    const calls = stubOpenAi(coach());
    await start("r1", "Home");
    await settle(t);
    expect(builds(calls)[0]!.input.placesTheCoachKnows).toEqual([
      { name: "Gym", equipment: "Rack, barbell, machines", knowledge: "partial", lastUsedForThisActivity: false },
      { name: "Home", equipment: "Two dumbbells", knowledge: "partial", lastUsedForThisActivity: true },
    ]);
  });

  it("a known name (any spelling) maps to that place; no new place is made", async () => {
    stubOpenAi(coach("  gYm "));
    await start("r1", "Home");
    await settle(t);
    expect(await get("r1")).toMatchObject({ status: "ready", proposal: { place: { placeId: "p-gym", name: "Gym" } } });
    expect(await places()).toHaveLength(2);
  });

  it("a new name makes a place with an empty text, and the next request finds it by key", async () => {
    stubOpenAi(coach("Hotel gym"));
    await start("r1", "Home");
    await settle(t);
    const proposal = (await get("r1"))!.proposal!;
    expect(proposal.place).toMatchObject({ name: "Hotel gym" });
    const all = await places();
    expect(all).toHaveLength(3);
    expect(all.find((p) => p.name === "Hotel gym")).toMatchObject({ placeId: proposal.place!.placeId, text: "" });
    stubOpenAi(coach("hotel   GYM"));
    await start("r2", "Home");
    await settle(t);
    expect((await get("r2"))!.proposal!.place!.placeId).toBe(proposal.place!.placeId);
    expect(await places()).toHaveLength(3);
  });

  it("no place from the coach: the place of the newest session of this activity", async () => {
    await saveSession({ ...setsSession("h1", NOW - 5 * DAY, "Home"), placeId: "p-gym" });
    await saveSession({ ...setsSession("h2", NOW - 2 * DAY, "Home"), placeId: "p-home" });
    await saveSession({ ...pushSession("g1", NOW - DAY), placeId: "p-gym" }); // another activity, newer
    stubOpenAi(coach());
    await start("r1", "Home");
    await settle(t);
    expect((await get("r1"))!.proposal!.place).toEqual({ placeId: "p-home", name: "Home" });
  });

  it("on the rules fallback (no AI) the same last place is used", async () => {
    await saveSession({ ...setsSession("h1", NOW - 2 * DAY, "Home"), placeId: "p-home" });
    await start("r1", "Home");
    await settle(t);
    expect(await get("r1")).toMatchObject({ status: "ready", proposal: { plan: { source: "rules" }, place: { placeId: "p-home", name: "Home" } } });
  });

  it("no place when the activity has no session, when its newest session has no place, or when that place is unknown", async () => {
    stubOpenAi(coach());
    await start("r1", "Padel");
    await saveSession(setsSession("h1", NOW - DAY, "Home")); // no place
    await start("r2", "Home");
    await saveSession({ ...setsSession("w1", NOW - DAY, "Work"), placeId: "ahead" }); // the app is ahead of the server
    await start("r3", "Work");
    await settle(t);
    for (const id of ["r1", "r2", "r3"]) {
      const g = await get(id);
      expect(g).toMatchObject({ status: "ready" });
      expect(g!.proposal).not.toHaveProperty("place");
    }
  });

  it("a session marked as deleted does not decide the place", async () => {
    await saveSession({ ...setsSession("h1", NOW - 5 * DAY, "Home"), placeId: "p-gym" });
    await saveSession({ ...setsSession("h2", NOW - 2 * DAY, "Home"), placeId: "p-home" });
    await t.mutation(api.commands.sessions.remove, { token: TOKEN, sessionId: "h2" });
    stubOpenAi(coach());
    await start("r1", "Home");
    await settle(t);
    expect((await get("r1"))!.proposal!.place!.placeId).toBe("p-gym");
  });

  it("a request with no name takes the coach's place name", async () => {
    stubOpenAi(coach("Home"));
    await start("r1", undefined, "quick workout");
    await settle(t);
    expect((await get("r1"))!.proposal!.place).toEqual({ placeId: "p-home", name: "Home" });
  });
});

describe("learn_place", () => {
  it("the prompt is short, takes the place, the others and the sentence, and the fallback changes nothing", () => {
    const i = { place: { name: "Home", equipment: "Dumbbells" }, otherPlaces: ["Gym"], sentence: "no bench here" };
    const p = learnPlaceJob.build(i);
    expect(JSON.parse(p.messages[0]!.content.split("INPUT_JSON:\n")[1]!)).toEqual(i);
    expect(p.system).toContain("THIS place");
    expect(learnPlaceJob.fallback(i)).toEqual({ changed: false, equipment: "Dumbbells" });
    expect(learnPlaceJob.output.safeParse({ changed: true, equipment: "x".repeat(1501) }).success).toBe(false);
  });

  it("changed: the text is written and a trace row keeps the source, the quote, before and after (feedback trigger)", async () => {
    await place("p-home", "Home", "Dumbbells");
    await place("p-gym", "Gym");
    stubOpenAi(coach("Home"));
    await start("r1", "Home", "quick");
    await settle(t);
    const calls = stubOpenAi(coach("Home", { changed: true, equipment: "Dumbbells. No bench." }));
    await again("r2", "r1", "there is no bench at home, only dumbbells");
    await settle(t);
    expect(learns(calls)).toHaveLength(1);
    expect(learns(calls)[0]!.input).toEqual({ place: { name: "Home", equipment: "Dumbbells" }, otherPlaces: ["Gym"], sentence: "there is no bench at home, only dumbbells" });
    expect((await places()).find((p) => p.placeId === "p-home")!.text).toBe("Dumbbells. No bench.");
    expect((await changes()).filter((c) => c.source === "feedback")).toMatchObject([
      { placeId: "p-home", source: "feedback", quote: "there is no bench at home, only dumbbells", before: "Dumbbells", after: "Dumbbells. No bench." },
    ]);
  });

  it("the note trigger: a request with a note reads the note, source note; the reply is not blocked", async () => {
    await place("p-home", "Home", "Dumbbells");
    const calls = stubOpenAi(coach("Home", { changed: true, equipment: "Dumbbells, a pull-up bar" }));
    await start("r1", "Home", "I put a pull-up bar up");
    expect((await get("r1"))!.status).toBe("pending");
    await settle(t);
    expect(await get("r1")).toMatchObject({ status: "ready" });
    expect(learns(calls)[0]!.input.sentence).toBe("I put a pull-up bar up");
    expect((await changes()).filter((c) => c.source !== "user")).toMatchObject([{ source: "note", quote: "I put a pull-up bar up", before: "Dumbbells", after: "Dumbbells, a pull-up bar" }]);
  });

  it("no sentence, no place, or a failed request: the job does not run", async () => {
    await place("p-home", "Home", "Dumbbells");
    const calls = stubOpenAi(coach("Home"));
    await start("r1", "Home"); // no note
    await start("r2", "Padel", "a note"); // the coach gives Home... then the place exists; this one has a note
    await settle(t);
    expect(learns(calls)).toHaveLength(1); // only r2
    const none = stubOpenAi(coach());
    await start("r3", "Padel", "note, but no place can be found");
    await settle(t);
    expect(learns(none)).toHaveLength(0);
  });

  it("unchanged: changed false writes nothing and logs nothing", async () => {
    await place("p-home", "Home", "Dumbbells");
    stubOpenAi(coach("Home", { changed: false, equipment: "Something else entirely" }));
    await start("r1", "Home", "nothing about equipment");
    await settle(t);
    expect((await places())[0]!.text).toBe("Dumbbells");
    expect(await changes()).toHaveLength(1); // the one of the place command (user), none of the job
  });

  it("changed true with the same text writes nothing and logs nothing", async () => {
    await place("p-home", "Home", "Dumbbells");
    stubOpenAi(coach("Home", { changed: true, equipment: "Dumbbells" }));
    await start("r1", "Home", "same");
    await settle(t);
    expect(await changes()).toHaveLength(1);
  });

  it("fallback: with no AI the note stays and nothing is logged", async () => {
    await place("p-home", "Home", "Dumbbells");
    await saveSession({ ...setsSession("h1", NOW - DAY, "Home"), placeId: "p-home" });
    await start("r1", "Home", "no bench");
    await settle(t);
    expect(await get("r1")).toMatchObject({ status: "ready", proposal: { place: { placeId: "p-home" } } });
    expect((await places())[0]!.text).toBe("Dumbbells");
    expect(await changes()).toHaveLength(1);
  });

  it("a bad answer (too long) is retried and then ignored", async () => {
    await place("p-home", "Home", "Dumbbells");
    stubOpenAi(coach("Home", { changed: true, equipment: "x".repeat(2000) }));
    await start("r1", "Home", "lots of kit");
    await settle(t);
    expect((await places())[0]!.text).toBe("Dumbbells");
  });

  it("a newer edit by the user wins over a job that read the old text", async () => {
    await place("p-home", "Home", "Dumbbells");
    await place("p-home", "Home", "Dumbbells and a bench");
    const wrote = await t.mutation(internal.jobs.places.learnSave, { userId: "owner", placeId: "p-home", source: "chat", sentence: "s", before: "Dumbbells", equipment: "Dumbbells, bands" });
    expect(wrote).toBe(false);
    expect((await places())[0]!.text).toBe("Dumbbells and a bench");
    expect(await t.mutation(internal.jobs.places.learnSave, { userId: "owner", placeId: "gone", source: "chat", sentence: "s", before: "", equipment: "x" })).toBe(false);
  });
});
