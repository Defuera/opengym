import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "../functions/_generated/api";
import { TOKEN, pushSession, setup, settle, type T } from "./helpers";

let t: T;
beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(Date.UTC(2026, 10, 17, 12));
  t = setup();
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

const limit = (over: Record<string, unknown> = {}) => ({ limitId: "k1", part: "left_knee", title: "Left knee", status: "active" as const, rules: [{ kind: "avoid" as const, text: "No deep squats", exercises: ["Squat"] }], ...over });
const saveLimit = (l: ReturnType<typeof limit>) => t.mutation(api.commands.limits.save, { token: TOKEN, limit: l });
const get = () => t.query(api.queries.aboutMe.get, { token: TOKEN });
const saveSession = (s: ReturnType<typeof pushSession>) => t.mutation(api.commands.sessions.save, { token: TOKEN, session: s });
const record = (over: Record<string, unknown> = {}) => ({ recordId: "r1", limitId: "k1", title: "Scan", text: "words, word for word", ...over });
const legSession = (id: string, endedAt: number) => ({ ...pushSession(id, endedAt), focus: "Legs", exercises: [{ name: "Leg Press", sets: [{ reps: 8, kg: 100, max: false }] }] });

describe("limit commands", () => {
  it("upsert is idempotent and a resend does not ask for a rebuild", async () => {
    await saveLimit(limit());
    await settle(t);
    const runs = (await t.run((c) => c.db.query("rebuilds").first()))!.runs;
    await saveLimit(limit());
    await settle(t);
    expect((await t.run((c) => c.db.query("rebuilds").first()))!.runs).toBe(runs);
    expect(await t.run((c) => c.db.query("limits").collect())).toHaveLength(1);
    await saveLimit(limit({ title: "Knee", status: "improving", since: "2026-03" }));
    const { limits } = await get();
    expect(limits).toHaveLength(1);
    expect(limits[0]).toMatchObject({ limitId: "k1", title: "Knee", status: "improving", since: "2026-03", records: [], checkins: [] });
    await settle(t);
  });

  it("validates input", async () => {
    await expect(saveLimit(limit({ part: "elbow" }))).rejects.toThrow(/part/);
    await expect(saveLimit(limit({ title: "" }))).rejects.toThrow(/title/);
    await expect(saveLimit(limit({ since: "2026-13" }))).rejects.toThrow(/since/);
    await expect(saveLimit(limit({ rules: Array.from({ length: 13 }, () => ({ kind: "do", text: "x" })) }))).rejects.toThrow(/rules/);
    await expect(saveLimit(limit({ rules: [{ kind: "avoid", text: "x".repeat(121) }] }))).rejects.toThrow(/text/);
    await expect(t.mutation(api.commands.limits.save, { token: "bad", limit: limit() })).rejects.toThrow(/unauthorized/);
    await saveLimit(limit());
    await expect(t.mutation(api.commands.limits.addRecord, { token: TOKEN, record: record({ date: "17.11.2026" }) })).rejects.toThrow(/date/);
    await expect(t.mutation(api.commands.limits.addRecord, { token: TOKEN, record: record({ text: "" }) })).rejects.toThrow(/text/);
    await expect(t.mutation(api.commands.limits.addRecord, { token: TOKEN, record: record({ limitId: "nope" }) })).rejects.toThrow(/not found/);
    await expect(t.mutation(api.commands.limits.checkin, { token: TOKEN, checkin: { checkinId: "c", limitId: "nope", at: 1, feeling: "fine" } })).rejects.toThrow(/not found/);
    await settle(t);
  });

  it("records and check-ins upsert; remove cascades; removeRecord is quiet", async () => {
    await saveLimit(limit());
    await saveLimit(limit({ limitId: "w1", part: "wrists", title: "Wrists" }));
    const addRecord = (r: ReturnType<typeof record>) => t.mutation(api.commands.limits.addRecord, { token: TOKEN, record: r });
    await addRecord(record());
    await addRecord(record({ text: "edited" }));
    await addRecord(record({ recordId: "r2", limitId: "w1" }));
    const checkin = (id: string, limitId: string, at: number) => t.mutation(api.commands.limits.checkin, { token: TOKEN, checkin: { checkinId: id, limitId, at, feeling: "noticed" as const } });
    await checkin("c1", "k1", 10);
    await checkin("c1", "k1", 11);
    await checkin("c2", "w1", 12);
    expect(await t.run((c) => c.db.query("records").collect())).toHaveLength(2);
    expect(await t.run((c) => c.db.query("checkins").collect())).toHaveLength(2);
    expect((await get()).limits.find((l) => l.limitId === "k1")!.records[0]).toEqual({ recordId: "r1", title: "Scan", text: "edited" });

    expect(await t.mutation(api.commands.limits.remove, { token: TOKEN, limitId: "k1" })).toBe(true);
    expect(await t.mutation(api.commands.limits.remove, { token: TOKEN, limitId: "k1" })).toBe(false);
    expect((await t.run((c) => c.db.query("records").collect())).map((r) => r.recordId)).toEqual(["r2"]);
    expect((await t.run((c) => c.db.query("checkins").collect())).map((r) => r.checkinId)).toEqual(["c2"]);
    expect(await t.mutation(api.commands.limits.removeRecord, { token: TOKEN, recordId: "r2" })).toBe(true);
    expect(await t.mutation(api.commands.limits.removeRecord, { token: TOKEN, recordId: "r2" })).toBe(false);
    await settle(t);
  });
});

describe("aboutMe:get", () => {
  it("orders limits active, improving, cleared, then title; records newest first; check-ins newest first, max 20, with labels", async () => {
    await saveLimit(limit({ limitId: "a", title: "Zed", status: "cleared" }));
    await saveLimit(limit({ limitId: "b", title: "Beta", status: "improving" }));
    await saveLimit(limit({ limitId: "c", title: "Beta", status: "active" }));
    await saveLimit(limit({ limitId: "d", title: "Alpha", status: "active" }));
    expect((await get()).limits.map((l) => l.limitId)).toEqual(["d", "c", "b", "a"]);

    const rec = (recordId: string, date?: string) => t.mutation(api.commands.limits.addRecord, { token: TOKEN, record: record({ recordId, limitId: "d", ...(date ? { date } : {}) }) });
    await rec("old", "2025-01-01");
    await rec("new", "2026-05-01");
    await rec("none");
    expect((await get()).limits[0]!.records.map((r) => r.recordId)).toEqual(["new", "old", "none"]);

    await saveSession(pushSession("s1", Date.UTC(2026, 10, 16)));
    await t.mutation(api.commands.sessions.save, { token: TOKEN, session: { sessionId: "s2", kind: "activity", type: "Cycling", startedAt: 1, endedAt: 2, exercises: [], source: "app" } });
    for (let i = 0; i < 22; i++) await t.mutation(api.commands.limits.checkin, { token: TOKEN, checkin: { checkinId: `c${i}`, limitId: "d", at: 1000 + i, feeling: "fine", ...(i === 21 ? { sessionId: "s1" } : i === 20 ? { sessionId: "s2" } : i === 19 ? { sessionId: "gone" } : {}) } });
    const ch = (await get()).limits[0]!.checkins;
    expect(ch).toHaveLength(20);
    expect(ch[0]).toEqual({ checkinId: "c21", at: 1021, feeling: "fine", sessionId: "s1", sessionLabel: "Gym, Push" });
    expect(ch[1]).toMatchObject({ checkinId: "c20", sessionLabel: "Cycling" });
    expect(ch[2]).toEqual({ checkinId: "c19", at: 1019, feeling: "fine", sessionId: "gone" });
    expect(ch[19]!.at).toBe(1002);
    await settle(t);
  });

  it("returns load for every muscle in both windows and the focus parts from goals", async () => {
    await t.mutation(api.commands.goals.create, { token: TOKEN, goalId: "g", title: "Bench 80", kind: "strength", exercise: "Bench press", targetKg: 80 });
    await saveSession(pushSession("recent", Date.UTC(2026, 10, 16)));
    await saveSession(pushSession("old", Date.UTC(2026, 8, 20), 60, "Push")); // 58 days before
    const r = await get();
    expect(Object.keys(r.load.d14)).toHaveLength(14);
    expect(Object.keys(r.load.d90)).toHaveLength(14);
    expect(r.load.d14.chest).toBe(3);
    expect(r.load.d14.quads).toBe(0);
    expect(r.focusParts).toEqual(["chest"]);
    expect((await get()).limits).toEqual([]);
    await settle(t);
  });
});

describe("aboutMe:askAfter", () => {
  const ask = (sessionId: string) => t.query(api.queries.aboutMe.askAfter, { token: TOKEN, sessionId });

  it("lists non-cleared limits the session loaded that have no check-in for it", async () => {
    await saveLimit(limit());
    await saveLimit(limit({ limitId: "w1", part: "wrists", title: "Wrists" }));
    await saveLimit(limit({ limitId: "c1", part: "right_knee", title: "Cleared knee", status: "cleared" }));
    await saveSession(legSession("leg1", Date.UTC(2026, 10, 16)));
    expect(await ask("leg1")).toEqual([{ limitId: "k1", title: "Left knee", part: "left_knee" }]);

    await t.mutation(api.commands.limits.checkin, { token: TOKEN, checkin: { checkinId: "x", limitId: "k1", sessionId: "other", at: 1, feeling: "fine" } });
    expect(await ask("leg1")).toHaveLength(1); // a check-in for another session does not count
    await t.mutation(api.commands.limits.checkin, { token: TOKEN, checkin: { checkinId: "y", limitId: "k1", sessionId: "leg1", at: 2, feeling: "bad" } });
    expect(await ask("leg1")).toEqual([]);

    await saveSession(pushSession("push1", Date.UTC(2026, 10, 16))); // chest, triceps: loads wrists
    expect(await ask("push1")).toEqual([{ limitId: "w1", title: "Wrists", part: "wrists" }]);
    expect(await ask("unknown")).toEqual([]);
    await settle(t);
  });
});
