import { v } from "convex/values";
import { query } from "../_generated/server";
import { requireToken } from "../lib/auth";
import { liveProgramDocs } from "../lib/programsDb";
import { liveSessionDocs } from "../lib/db";
import { fillKg, localDate, programNow } from "../model/program";

/**
 * Every live program, newest first, each with a `now` block (see docs/api-contract.md): the state against today's date in APP_TIMEZONE,
 * the week, the slots of this week with done or not, and `next` with the written session of the current phase and the kg of the last
 * time filled in by code (model/program.ts fillKg). A slot is done when a live session has this programId, programWeek and programSlot.
 * Needs no AI and writes nothing.
 */
export const list = query({
  args: { token: v.string() },
  handler: async (ctx, { token }) => {
    requireToken(token);
    const programs = await liveProgramDocs(ctx);
    if (programs.length === 0) return [];
    // The whole live log, newest first: slots and kg come from it. An activity row has no exercises, so it adds nothing to the kg.
    const log = await liveSessionDocs(ctx, { order: "desc" });
    const today = localDate(Date.now());
    return programs.map((p) => {
      const mine = log.filter((s) => s.programId === p.programId);
      const done = new Set(mine.map((s) => `${s.programWeek}:${s.programSlot}`));
      const now = programNow(p, today, (week, slot) => done.has(`${week}:${slot}`), (session) => fillKg(session.exercises, mine.find((s) => s.programKey === session.key) ?? null, log));
      return { programId: p.programId, title: p.title, purpose: p.purpose, status: p.status, startsOn: p.startsOn, endsOn: p.endsOn, week: p.week, phases: p.phases, rules: p.rules, tests: p.tests, rev: p.rev, now };
    });
  },
});
