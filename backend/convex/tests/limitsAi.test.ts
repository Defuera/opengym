import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "../functions/_generated/api";
import { buildDashboardJob } from "../functions/model/ai/jobs/buildDashboard";
import { chatJob } from "../functions/model/ai/jobs/chat";
import { extractFromChatJob } from "../functions/model/ai/jobs/extractFromChat";
import { buildPlanInput, buildReviewInput } from "../functions/model/ai/jobs/inputs";
import { buildSessionJob } from "../functions/model/ai/jobs/buildSession";
import { coachPicture } from "../functions/model/ai/jobs/coachPicture";
import { planSessionJob } from "../functions/model/ai/jobs/planSession";
import { reviewSessionJob } from "../functions/model/ai/jobs/reviewSession";
import { summariseThreadJob } from "../functions/model/ai/jobs/summariseThread";
import { titleThreadJob } from "../functions/model/ai/jobs/titleThread";
import { LIMITS_RULE } from "../functions/model/ai/promptRules";
import { assembleCoachContext } from "../functions/model/coachContext";
import type { Limit, Session } from "../functions/model/schema";
import { TOKEN, setup, settle, type T } from "./helpers";

const MARKER = "ZX-RECORD-MARKER-4471";
const session = (id: string, names: string[]): Session => ({
  id, kind: "gym", type: "Gym", focus: "Legs", startedAt: 1_000_000, endedAt: 5_000_000, source: "app",
  exercises: names.map((name) => ({ name, sets: [{ reps: 8, kg: 50, max: false }] })),
});
const limit: Limit & { records: unknown[] } = {
  limitId: "k1", part: "left_knee", title: "Left knee", status: "active",
  rules: [{ kind: "avoid", text: "No deep squats", exercises: ["Squat"] }, { kind: "do", text: "Leg press, short range" }],
  records: [{ recordId: "r1", title: "Scan", text: MARKER }], // a caller that leaks a record by mistake
};
const cleared: Limit = { limitId: "k2", part: "wrists", title: "Wrists", status: "cleared", rules: [{ kind: "light", text: "CLEARED-RULE" }] };

describe("prompts carry limits and never records", () => {
  const log = [session("a", ["Squat", "Leg Press"])];
  const prompts = (limits: Limit[]) => {
    const plan = buildPlanInput(log, [], [], "Gym", "Legs", limits);
    const review = buildReviewInput(log, log[0]!, limits);
    const coach = assembleCoachContext({ otherThreads: [], sessions: log, goals: [], context: [], limits }, [], false);
    return {
      plan: planSessionJob.build(plan),
      review: reviewSessionJob.build(review),
      session: buildSessionJob.build({ name: null, note: "", request: "legs at home, 20 min", picture: coachPicture(log, [], [], limits, [], 6_000_000), limits }),
      chat: chatJob.build({ contextBlock: coach.contextBlock, history: [{ role: "user", content: "hi" }] }),
      dashboard: buildDashboardJob.build({ days: 7, sessions: log, goals: [], context: [] }),
      extract: extractFromChatJob.build({ text: "hi", existingContext: [], existingGoals: [] }),
      summarise: summariseThreadJob.build({ title: "t", messages: [{ role: "user", text: "hi" }] }),
      title: titleThreadJob.build({ text: "hi", reply: "hello" }),
    };
  };
  const whole = (p: { system: string; messages: { content: string }[] }) => `${p.system}\n${p.messages.map((m) => m.content).join("\n")}`;

  it("no job prompt holds a record, even when a limit object carries one", () => {
    for (const [name, p] of Object.entries(prompts([limit, cleared]))) expect(whole(p), name).not.toContain(MARKER);
  });

  it("plan, review, session and chat get non-cleared limits as {part,title,status,rules:[{kind,text}]} and the one-sentence rule", () => {
    const p = prompts([limit, cleared]);
    const expected = [{ part: "left_knee", title: "Left knee", status: "active", rules: [{ kind: "avoid", text: "No deep squats" }, { kind: "do", text: "Leg press, short range" }] }];
    for (const name of ["plan", "review", "session"] as const) {
      const data = JSON.parse(p[name].messages[0]!.content.split("INPUT_JSON:\n")[1]!);
      expect(data.limits, name).toEqual(expected);
      if (name !== "session") expect(p[name].system, name).toContain(LIMITS_RULE);
    }
    expect(p.chat.system).toContain(LIMITS_RULE);
    expect(p.chat.system).toContain('"part":"left_knee"');
    for (const name of ["plan", "review", "session", "chat"] as const) expect(whole(p[name]), name).not.toContain("CLEARED-RULE");
  });
});

describe("hard check on avoid rules (stubbed network)", () => {
  let t: T;
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(Date.UTC(2026, 10, 17, 12));
    t = setup();
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
  });

  const stub = (reply: (job: string, attempt: number) => string) => {
    vi.stubEnv("AI_PROVIDER", "openai");
    vi.stubEnv("OPENAI_API_KEY", "k");
    vi.stubEnv("OPENAI_MODEL", "m");
    const bodies: { job: string; text: string }[] = [];
    const seen: Record<string, number> = {};
    vi.stubGlobal("fetch", async (_u: string, init: RequestInit) => {
      const body = JSON.parse(init.body as string);
      const text = JSON.stringify(body.messages);
      const job = (body.messages[0].content as string).match(/^JOB: (\w+)/m)?.[1] ?? "";
      seen[job] = (seen[job] ?? 0) + 1;
      bodies.push({ job, text });
      return new Response(JSON.stringify({ choices: [{ message: { content: reply(job, seen[job]!) } }] }), { status: 200 });
    });
    return bodies;
  };
  const setupData = async () => {
    await t.mutation(api.commands.limits.save, { token: TOKEN, limit: { limitId: "k1", part: "left_knee", title: "Left knee", status: "active", rules: [{ kind: "avoid", text: "No deep squats", exercises: ["squat"] }] } });
    await t.mutation(api.commands.limits.addRecord, { token: TOKEN, record: { recordId: "r1", limitId: "k1", title: "Scan", text: MARKER } });
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: { sessionId: "s1", kind: "gym", type: "Gym", focus: "Legs", startedAt: 1, endedAt: Date.UTC(2026, 10, 16), exercises: [{ name: "Squat", sets: [{ reps: 5, kg: 80, max: false }] }, { name: "Leg Press", sets: [{ reps: 8, kg: 100, max: false }] }], source: "app" } });
  };
  const plan = () => t.query(api.queries.plans.next, { token: TOKEN, focus: "Legs" });
  const planJson = (...names: string[]) => JSON.stringify({ rationale: "r", exercises: names.map((name) => ({ name, sets: [{ reps: 5, kg: 50, max: false }] })) });

  it("a plan with an avoided exercise is retried, then the fallback is used and it drops the exercise", async () => {
    const bodies = stub((job) => (job === "plan_session" ? planJson("Squat", "Leg Press") : job === "predict_activity" ? JSON.stringify({ predictions: [{ kind: "gym", type: "Gym", focus: "Legs", reason: "r" }] }) : job === "review_session" ? JSON.stringify({ summary: "s", changes: [] }) : "{}"));
    await setupData();
    await settle(t);
    expect(bodies.filter((b) => b.job === "plan_session")).toHaveLength(2);
    const { plan: p } = await plan();
    expect(p.source).toBe("rules");
    expect(p.exercises.map((e) => e.name)).toEqual(["Leg Press"]);
    // The retry turn tells the model what was wrong.
    expect(bodies.filter((b) => b.job === "plan_session")[1]!.text).toContain("marked avoid");
    // No request of any job holds the record text.
    expect(bodies.length).toBeGreaterThan(3);
    for (const b of bodies) expect(b.text, b.job).not.toContain(MARKER);
  });

  it("a plan without avoided exercises is accepted as AI; a second valid try after an invalid one is accepted", async () => {
    stub((job, n) => (job === "plan_session" ? (n === 1 ? planJson("Squat") : planJson("Leg Extension")) : "{}"));
    await setupData();
    await settle(t);
    const { plan: p } = await plan();
    expect(p.source).toBe("ai");
    expect(p.exercises.map((e) => e.name)).toEqual(["Leg Extension"]);
  });

  it("a cleared limit no longer blocks the exercise", async () => {
    stub((job) => (job === "plan_session" ? planJson("Squat") : "{}"));
    await setupData();
    await t.mutation(api.commands.limits.save, { token: TOKEN, limit: { limitId: "k1", part: "left_knee", title: "Left knee", status: "cleared", rules: [{ kind: "avoid", text: "No deep squats", exercises: ["Squat"] }] } });
    await settle(t);
    const { plan: p } = await plan();
    expect(p).toMatchObject({ source: "ai" });
    expect(p.exercises.map((e) => e.name)).toEqual(["Squat"]);
  });

  it("the chat coach reads the limits, not the record", async () => {
    const bodies = stub((job) => (job === "coach_turn" ? '{"message":"ok"}' : "{}"));
    await setupData();
    await t.mutation(api.commands.threads.create, { token: TOKEN, threadId: "th", title: "T" });
    await t.mutation(api.commands.messages.send, { token: TOKEN, threadId: "th", messageId: "m1", text: "What next?" });
    await settle(t);
    const chat = bodies.filter((b) => b.job === "coach_turn");
    expect(chat).toHaveLength(1);
    expect(chat[0]!.text).toContain("No deep squats");
    for (const b of bodies) expect(b.text, b.job).not.toContain(MARKER);
  });
});
