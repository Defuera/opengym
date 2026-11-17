import { afterEach, describe, expect, it } from "vitest";
import { setup } from "./helpers";

let h: ReturnType<typeof setup>;
afterEach(() => h?.cleanup());

const gym = (startedAt: number) => ({
  kind: "gym",
  type: "Push",
  startedAt,
  endedAt: startedAt + 3_600_000,
  exercises: [{ name: "Bench press", sets: [{ reps: 5, kg: 60, max: false }] }],
});
const body = () => ({
  sessions: [gym(1_000_000), { ...gym(9_000_000), id: "keep-me" }, { kind: "activity", type: "Run", startedAt: 20_000_000, endedAt: 21_800_000, minutes: 30, distanceKm: 5 }],
  goals: [{ title: "Bench 80", kind: "strength", exercise: "Bench press", targetKg: 80 }],
  context: [{ text: "Left ankle is tight", topic: "ankle" }],
  note: "from spreadsheet",
});

describe("POST /v1/import/structured", () => {
  it("loads ready items as one done job without per-session reviews", async () => {
    h = setup();
    const r = await h.call("POST", "/v1/import/structured", body());
    expect(r.status).toBe(200);
    const { job } = r.json;
    expect(job).toMatchObject({ status: "done", total: 5, processed: 5, counts: { sessions: 3, goals: 1, context: 1 }, notes: ["from spreadsheet"] });

    const { sessions } = (await h.call("GET", "/v1/sessions")).json;
    expect(sessions).toHaveLength(3);
    for (const s of sessions) expect(s).toMatchObject({ source: "import", importId: job.id });
    expect(sessions.map((s: { id: string }) => s.id)).toContain("keep-me");
    expect((await h.call("GET", "/v1/goals")).json.goals[0]).toMatchObject({ status: "active", source: "import", importId: job.id });
    expect((await h.call("GET", "/v1/context")).json.items[0]).toMatchObject({ active: true, source: "import", importId: job.id });

    await h.queue.drain();
    for (const s of sessions) expect(h.repos.reviews.get(s.id)).toBeNull();
    expect((await h.call("GET", `/v1/import/${job.id}`)).json.job.id).toBe(job.id);
  });

  it("answers 400 naming the bad item and stores nothing", async () => {
    h = setup();
    const b = body();
    b.sessions[2] = { ...gym(5_000), endedAt: 1_000 };
    const r = await h.call("POST", "/v1/import/structured", b);
    expect(r.status).toBe(400);
    expect(r.json.error).toContain("sessions[2]");
    expect(r.json.error).toContain("endedAt must not be before startedAt");
    const bad = await h.call("POST", "/v1/import/structured", { ...body(), goals: [{ title: "", kind: "strength" }] });
    expect(bad.json.error).toContain("goals[0]");
    expect((await h.call("GET", "/v1/sessions")).json.sessions).toHaveLength(0);
    expect((await h.call("GET", "/v1/goals")).json.goals).toHaveLength(0);
    expect((await h.call("GET", "/v1/context")).json.items).toHaveLength(0);
    expect((await h.call("GET", "/v1/import")).json.jobs).toHaveLength(0);
  });

  it("DELETE /v1/import/:id removes sessions, goal and context", async () => {
    h = setup();
    const { job } = (await h.call("POST", "/v1/import/structured", body())).json;
    expect((await h.call("DELETE", `/v1/import/${job.id}`)).status).toBe(200);
    expect((await h.call("GET", "/v1/sessions")).json.sessions).toHaveLength(0);
    expect((await h.call("GET", "/v1/goals")).json.goals).toHaveLength(0);
    expect((await h.call("GET", "/v1/context")).json.items).toHaveLength(0);
    expect((await h.call("GET", `/v1/import/${job.id}`)).status).toBe(404);
  });
});
