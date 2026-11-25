import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "../functions/_generated/api";
import { CoachActionSchema } from "../functions/model/coachTools";
import { sessionPlaceDetail } from "../functions/model/actionDetail";
import { TOKEN, setup, settle, stubOpenAi, type T } from "./helpers";

/** ADR-035: the coach changes the place of the open session when the person says where they train. */
let t: T;
beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(Date.UTC(2026, 10, 25, 10));
  t = setup();
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

const PLAN = [{ name: "Bench press", sets: [{ reps: 8, kg: 60, max: false }] }, { name: "Cable row", sets: [{ reps: 10, kg: 40, max: false }] }];
async function world(withSession = true) {
  await t.mutation(api.commands.places.save, { token: TOKEN, placeId: "p-gym", name: "Gym", text: "Rack, barbell, cables" });
  await t.mutation(api.commands.places.save, { token: TOKEN, placeId: "p-home", name: "Home", text: "Dumbbells" });
  if (withSession) await t.mutation(api.commands.openSession.put, { token: TOKEN, session: { id: "s1", kind: "gym", type: "Gym", startedAt: 1000, placeId: "p-home", exercises: [{ id: "e1", name: "Goblet squat", sets: [{ reps: 10, kg: 12, max: false, done: false }], fresh: false, carry: false }] } });
  await t.mutation(api.commands.threads.create, { token: TOKEN, threadId: "th1", title: "Coach" });
}
const send = (text: string) => t.mutation(api.commands.messages.send, { token: TOKEN, threadId: "th1", messageId: "m1", text, context: { screen: "session", openSessionId: "s1" } });
const messages = () => t.query(api.queries.messages.list, { token: TOKEN, threadId: "th1" });
const turn = (actions: object[]) => () => JSON.stringify({ message: "ok", actions });
const answer = (reply: () => string) => stubOpenAi((job) => (job === "coach_turn" ? reply() : job === "summarise_thread" ? JSON.stringify({ summary: "s" }) : "{}"));

describe("set_session_place", () => {
  it("the schema accepts the tool and needs a placeId", () => {
    expect(CoachActionSchema.safeParse({ id: "a1", name: "set_session_place", arguments: { placeId: "p-gym" } }).success).toBe(true);
    expect(CoachActionSchema.safeParse({ id: "a1", name: "set_session_place", arguments: {} }).success).toBe(false);
  });

  it("the line reads Place: Home -> Gym", () => {
    expect(sessionPlaceDetail("Home", "Gym")).toBe("Place: Home → Gym");
    expect(sessionPlaceDetail(null, "Gym")).toBe("Place: Gym");
  });

  it("changes the place of the open session at once and reports it", async () => {
    await world();
    answer(turn([{ id: "a1", name: "set_session_place", arguments: { placeId: "p-gym" } }]));
    await send("I'm not at home, I'm going to the gym");
    await settle(t);
    const r = await t.query(api.queries.openSession.get, { token: TOKEN });
    expect(r).toMatchObject({ rev: 2, updatedBy: "coach" });
    expect(r.session!.placeId).toBe("p-gym");
    expect((await messages())[1]!.actions).toMatchObject([{ name: "set_session_place", status: "applied", detail: "Place: Home → Gym" }]);
  });

  it("an unknown place is rejected and nothing changes", async () => {
    await world();
    answer(turn([{ id: "a1", name: "set_session_place", arguments: { placeId: "p-nowhere" } }]));
    await send("I'm at the park");
    await settle(t);
    const r = await t.query(api.queries.openSession.get, { token: TOKEN });
    expect(r).toMatchObject({ rev: 1 });
    expect(r.session!.placeId).toBe("p-home");
    expect((await messages())[1]!.actions).toMatchObject([{ status: "rejected", reason: "no such place" }]);
  });

  it("is rejected when no session is open", async () => {
    await world(false);
    answer(turn([{ id: "a1", name: "set_session_place", arguments: { placeId: "p-gym" } }]));
    await send("I'm at the gym");
    await settle(t);
    expect((await messages())[1]!.actions).toMatchObject([{ status: "rejected", reason: "no session is open" }]);
  });

  it("goes with a rebuild in the same turn: the place is set and the plan is a proposal", async () => {
    await world();
    answer(turn([
      { id: "a1", name: "set_session_place", arguments: { placeId: "p-gym" } },
      { id: "a2", name: "rebuild_open_session", arguments: { exercises: PLAN } },
    ]));
    await send("I'm going to the gym, give me my usual upper body");
    await settle(t);
    const r = await t.query(api.queries.openSession.get, { token: TOKEN });
    expect(r.session!.placeId).toBe("p-gym");
    expect(r.session!.exercises.map((e) => e.name)).toEqual(["Goblet squat"]);
    const m = (await messages())[1]!;
    expect(m.actions).toMatchObject([{ name: "set_session_place", status: "applied" }, { name: "rebuild_open_session", status: "drafted" }]);
    expect(m.proposal).toBeTruthy();
  });
});
