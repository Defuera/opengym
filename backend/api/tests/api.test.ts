import { afterEach, describe, expect, it } from "vitest";
import { pushSession, setup } from "./helpers";

let h: ReturnType<typeof setup>;
afterEach(() => h?.cleanup());

describe("auth and validation", () => {
  it("health is open, other routes need the token", async () => {
    h = setup();
    expect((await h.call("GET", "/v1/health", undefined, {})).json).toMatchObject({ ok: true, provider: "mock", aiConfigured: true });
    expect((await h.call("GET", "/v1/goals", undefined, {})).status).toBe(401);
    expect((await h.call("GET", "/v1/goals", undefined, { authorization: "Bearer nope" })).status).toBe(401);
    expect((await h.call("GET", "/v1/goals")).status).toBe(200);
  });

  it("rejects bad sessions", async () => {
    h = setup();
    const good = pushSession("a", 1_000_000);
    const bad = [
      { ...good, kind: "weights" },
      { ...good, exercises: [{ name: "", sets: [] }] },
      { ...good, exercises: [{ name: "Bench press", sets: [{ reps: 101, kg: 10, max: false }] }] },
      { ...good, exercises: [{ name: "Bench press", sets: [{ reps: 5, kg: 501, max: false }] }] },
      { ...good, kind: "activity" },
      { ...good, endedAt: good.startedAt - 1 },
      { ...good, source: "ai" },
    ];
    for (const b of bad) expect((await h.call("PUT", "/v1/sessions/a", b)).status).toBe(400);
    expect((await h.call("PUT", "/v1/sessions/other", good)).status).toBe(400);
  });

  it("PUT session is an idempotent upsert; GET honours since", async () => {
    h = setup();
    const s = pushSession("s1", 2_000_000);
    await h.call("PUT", "/v1/sessions/s1", s);
    await h.call("PUT", "/v1/sessions/s1", s);
    await h.call("PUT", "/v1/sessions/s2", pushSession("s2", 3_000_000));
    expect((await h.call("GET", "/v1/sessions")).json.sessions.map((x: { id: string }) => x.id)).toEqual(["s1", "s2"]);
    expect((await h.call("GET", "/v1/sessions?since=2000000")).json.sessions).toHaveLength(1);
    expect((await h.call("DELETE", "/v1/sessions/s1")).json).toEqual({ ok: true });
    expect((await h.call("DELETE", "/v1/sessions/s1")).status).toBe(404);
  });

  it("lists the AI functions", async () => {
    h = setup();
    const { functions } = (await h.call("GET", "/v1/ai/functions")).json;
    expect(functions.map((f: { name: string }) => f.name)).toEqual(["plan_session", "predict_activity", "build_dashboard", "chat", "extract_from_chat", "summarise_thread", "review_session", "import_data"]);
  });
});

describe("rules fallbacks (AI off)", () => {
  it("Push with no history is the starter with bench defaults", async () => {
    h = setup({ provider: null });
    const { plan } = (await h.call("GET", "/v1/plans/next?type=Push")).json;
    expect(plan.source).toBe("rules");
    expect(plan.exercises.map((e: { name: string }) => e.name)).toEqual(["Bench press", "Overhead press", "Dips", "Triceps pushdown"]);
    expect(plan.exercises[0].sets).toEqual([
      { reps: 6, kg: 20, max: false },
      { reps: 6, kg: 40, max: false },
      { reps: 6, kg: 60, max: false },
      { reps: 1, kg: 60, max: true },
    ]);
  });

  it("after logging a Push session the plan repeats it", async () => {
    h = setup({ provider: null });
    const s = pushSession("p1", 5_000_000, 70);
    await h.call("PUT", "/v1/sessions/p1", s);
    const { plan } = (await h.call("GET", "/v1/plans/next?type=Push")).json;
    expect(plan.exercises.map((e: { name: string }) => e.name)).toEqual(["Bench press", "Dips"]);
    expect(plan.exercises[0].sets).toEqual(s.exercises[0]!.sets.map((x) => ({ reps: x.reps, kg: x.kg, max: x.max })));
  });

  it("start predictions rotate: longest-ago gym type first", async () => {
    h = setup({ provider: null });
    await h.call("PUT", "/v1/sessions/p1", pushSession("p1", 5_000_000));
    const { predictions } = (await h.call("GET", "/v1/start")).json;
    expect(predictions.map((p: { type: string }) => p.type)).toEqual(["Pull", "Legs", "Push"]);
  });

  it("chat gives the fixed reply but stores the message", async () => {
    h = setup({ provider: null });
    const t = (await h.call("POST", "/v1/threads", { title: "Knee" })).json.thread;
    const r = (await h.call("POST", `/v1/threads/${t.id}/messages`, { text: "hello" })).json;
    expect(r.assistantMessage.text).toContain("not available");
    expect(r.extracted).toEqual({ goals: [], context: [] });
    expect((await h.call("GET", `/v1/threads/${t.id}/messages`)).json.messages).toHaveLength(2);
  });
});

describe("plan safety limits", () => {
  it("caps weights at 1.25x the heaviest logged, plus exercise and set counts", async () => {
    const wild = {
      name: "wild",
      supportsImages: false,
      complete: async () =>
        JSON.stringify({
          rationale: "x",
          exercises: Array.from({ length: 15 }, (_, i) => ({ name: i === 0 ? "Bench press" : `Ex ${i}`, sets: Array.from({ length: 12 }, () => ({ reps: 5, kg: 200, max: false })) })),
        }),
    };
    h = setup({ provider: wild });
    await h.call("PUT", "/v1/sessions/p1", pushSession("p1", 5_000_000, 60));
    const { plan } = (await h.call("GET", "/v1/plans/next?type=Push")).json;
    expect(plan.source).toBe("ai");
    expect(plan.exercises).toHaveLength(12);
    expect(plan.exercises[0].sets).toHaveLength(10);
    expect(plan.exercises[0].sets[0].kg).toBe(75);
    expect(plan.exercises[1].sets[0].kg).toBe(200); // no history for that exercise
  });
});

describe("dashboard and invalidation", () => {
  it("returns computed modules", async () => {
    h = setup({ provider: null });
    await h.call("PUT", "/v1/sessions/p1", pushSession("p1", h.clock.t - 3_600_000, 60));
    await h.call("POST", "/v1/goals", { title: "Bench 80", kind: "strength", exercise: "Bench press", targetKg: 80 });
    const { dashboard } = (await h.call("GET", "/v1/dashboard?days=7")).json;
    expect(dashboard).toMatchObject({ days: 7, source: "rules" });
    const types = dashboard.modules.map((m: { type: string }) => m.type);
    expect(types).toEqual(["stat", "stat", "stat", "goal_progress", "recent_sessions"]);
    expect(dashboard.modules[0]).toMatchObject({ value: "1", highlighted: true });
    expect(dashboard.modules[2]).toMatchObject({ value: "60 kg" });
    expect(dashboard.modules[3]).toMatchObject({ current: "60 kg", target: "80 kg", fraction: 0.75 });
    expect((await h.call("GET", "/v1/dashboard?days=9")).status).toBe(400);
  });

  it("goal CRUD invalidates stored plans and dashboard layout, then regenerates", async () => {
    h = setup();
    await h.call("GET", "/v1/plans/next?type=Push");
    await h.queue.drain();
    await h.ctx.proposals.refreshDashboard(7);
    expect(h.repos.plans.get("Push")).not.toBeNull();
    expect(h.repos.dashboards.get(7)).not.toBeNull();

    const goal = (await h.call("POST", "/v1/goals", { title: "Train 3x", kind: "consistency", sessionsPerWeek: 3 })).json.goal;
    expect(h.repos.plans.get("Push")).toBeNull();
    expect(h.repos.dashboards.get(7)).toBeNull();
    await h.queue.drain();
    expect(h.repos.plans.get("Push")?.source).toBe("ai");
    expect(h.repos.dashboards.get(7)?.modules.some((m) => m.type === "goal_progress")).toBe(true);

    await h.call("PATCH", `/v1/goals/${goal.id}`, { status: "done" });
    expect(h.repos.plans.get("Push")).toBeNull();
    await h.queue.drain();
    await h.call("DELETE", `/v1/goals/${goal.id}`);
    expect(h.repos.plans.get("Push")).toBeNull();
    expect((await h.call("PATCH", "/v1/goals/nope", { status: "done" })).status).toBe(404);
  });

  it("session write produces a review in the background", async () => {
    h = setup();
    await h.call("PUT", "/v1/sessions/p1", pushSession("p1", 5_000_000));
    expect((await h.call("GET", "/v1/sessions/p1/review")).json.review).toBeNull();
    await h.queue.drain();
    expect((await h.call("GET", "/v1/sessions/p1/review")).json.review).toMatchObject({ sessionId: "p1", source: "ai" });
  });
});
