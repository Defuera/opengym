import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalAction, internalMutation, internalQuery } from "../_generated/server";
import { OWNER_USER_ID, OWNER_USER_ID as userId } from "../lib/currentUser";
import { PAGE_SIZE, PER_USER_TABLES } from "../lib/userTables";
import { ensureCategory } from "../lib/categoriesDb";
import { usedCategories } from "../model/entryCategory";
import { markFactsChanged } from "../lib/factsChanged";
import { isLegacyGym, normalizePredictions, normalizeSession } from "../model/sessionShape";

/** Sessions per call. A session holds its sets, so keep this well below the 16k-document limit of one mutation. */
const BATCH = 100;

/**
 * ADR-013, activity first. Run by hand once, after the schema change is deployed:
 *   internal.jobs.migrations.activityFirst   args: {}   (optional: { batch?: number })
 *
 * Phase 1 pages through `sessions`. Every gym session whose type is not "Gym" gets focus = old type
 * (an existing focus is kept) and type = "Gym". Activity sessions are not touched.
 * It schedules itself for the next page until the last one, then does phase 2 in the same call.
 *
 * Phase 2 fixes the stored read models that would break the new shape:
 * - plans: a row with the legacy `type` key gets `focus = type` and the `type` key removed.
 *   If a row for that focus already exists (a rebuild ran between the deploy and this migration),
 *   the older legacy row is a duplicate and is deleted. Nothing else is deleted.
 * - predictions: the single row's items are normalised (gym item -> type "Gym" + focus, Gym once).
 * - reviews and dashboards hold no gym type (a review has free text, a dashboard has layout specs), so they stay.
 * If anything changed it marks facts changed, so the debounced rebuild refreshes the read models.
 *
 * Idempotent: a second run finds nothing to change, writes nothing and does not trigger a rebuild.
 * Old one-off migration of the first user (ADR-039): it works on the owner's data only (`userId` below is the owner constant).
 * Returns what this call changed. `done` is false while more pages are scheduled.
 */
export const activityFirst = internalMutation({
  args: { cursor: v.optional(v.union(v.string(), v.null())), batch: v.optional(v.number()) },
  handler: async (ctx, { cursor, batch }) => {
    const page = await ctx.db.query("sessions").paginate({ cursor: cursor ?? null, numItems: Math.max(1, Math.floor(batch ?? BATCH)) });
    let sessions = 0;
    for (const d of page.page) {
      if (!isLegacyGym(d)) continue;
      const n = normalizeSession(d);
      await ctx.db.patch(d._id, { type: n.type, ...(n.focus !== undefined ? { focus: n.focus } : {}) });
      sessions++;
    }
    if (!page.isDone) {
      // Carry the count of this page into the rebuild decision: a later page may find nothing, so mark now.
      if (sessions > 0) await markFactsChanged(ctx, userId);
      await ctx.scheduler.runAfter(0, internal.jobs.migrations.activityFirst, { cursor: page.continueCursor, batch });
      return { sessions, plans: 0, predictions: 0, done: false };
    }

    let plans = 0;
    for (const p of await ctx.db.query("plans").collect()) {
      if (p.focus !== undefined || p.type === undefined) continue;
      const legacy = p.type;
      const existing = await ctx.db.query("plans").withIndex("by_focus", (q) => q.eq("focus", legacy)).first();
      if (existing) await ctx.db.delete(p._id);
      else await ctx.db.patch(p._id, { focus: legacy, type: undefined });
      plans++;
    }
    let predictions = 0;
    const pred = await ctx.db.query("predictions").first();
    if (pred) {
      const items = normalizePredictions(pred.items);
      if (JSON.stringify(items) !== JSON.stringify(pred.items)) {
        await ctx.db.patch(pred._id, { items });
        predictions = 1;
      }
    }
    if (sessions + plans + predictions > 0) await markFactsChanged(ctx, userId);
    return { sessions, plans, predictions, done: true };
  },
});

/**
 * ADR-031, category colours. Run by hand once after the deploy:
 *   internal.jobs.migrations.categoryColors   args: {}
 * Every label the entries already use (Meal, Training, ... and any made since) gets a stored category with a colour from plain code, most
 * used label first, with no AI call. A category that has a row is not touched, so a colour never changes. Entries are not changed.
 * Idempotent. Returns the labels it made a row for.
 */
export const categoryColors = internalMutation({
  args: {},
  handler: async (ctx) => {
    const entries = await ctx.db.query("entries").collect();
    const labels = usedCategories(entries.filter((e) => e.deletedAt === undefined).map((e) => e.read?.kind), 1000);
    const made: string[] = [];
    for (const label of labels) {
      const before = await ctx.db.query("entryCategories").collect();
      const row = await ensureCategory(ctx, userId, label, undefined, "rules");
      if (row && (await ctx.db.query("entryCategories").collect()).length > before.length) made.push(row.label);
    }
    return { made };
  },
});

const tableName = v.union(...PER_USER_TABLES.map((t) => v.literal(t)));

/** Makes the `users` row of the owner when it is missing. Returns true when it made it. */
export const ensureOwner = internalMutation({
  args: {},
  handler: async (ctx): Promise<boolean> => {
    if (await ctx.db.query("users").withIndex("by_userId", (q) => q.eq("userId", OWNER_USER_ID)).unique()) return false;
    await ctx.db.insert("users", { userId: OWNER_USER_ID, createdAt: Date.now() });
    return true;
  },
});

/** One page of one table: every row with no `userId` gets the owner. Returns what the page held and where the next one starts. */
export const assignOwnerPage = internalMutation({
  args: { table: tableName, cursor: v.optional(v.union(v.string(), v.null())), batch: v.optional(v.number()) },
  handler: async (ctx, { table, cursor, batch }): Promise<{ read: number; assigned: number; cursor: string; isDone: boolean }> => {
    const page = await ctx.db.query(table).paginate({ cursor: cursor ?? null, numItems: Math.max(1, Math.floor(batch ?? PAGE_SIZE[table])) });
    let assigned = 0;
    for (const row of page.page) {
      if ((row as { userId?: string }).userId !== undefined) continue;
      await ctx.db.patch(row._id, { userId: OWNER_USER_ID } as never);
      assigned++;
    }
    return { read: page.page.length, assigned, cursor: page.continueCursor, isDone: page.isDone };
  },
});

/**
 * ADR-039, deploy point 1: gives every old row to the owner. Run by hand once after deploy point 1:
 *   npx convex run jobs/migrations:assignOwner '{}'
 * Optional args: `{ batch?: number }` (rows per page; default per table, see lib/userTables.ts).
 * (a) makes the `users` row of the owner when it is missing; (b) walks every per-user table in pages (one mutation per page, so no call is
 * too big) and sets `userId: "owner"` on each row that has none; (c) returns per table `{ read, assigned }`, and `users` (true when it made the row).
 * Idempotent and resumable: a row that has a `userId` is never touched, so a second run (or a run after a stop) changes nothing more and
 * `assigned` is 0 everywhere. Writes made by the live app between the pages are safe: since deploy point 1 they carry the `userId` themselves.
 * Makes no rebuild and changes no other field.
 */
export const assignOwner = internalAction({
  args: { batch: v.optional(v.number()) },
  handler: async (ctx, { batch }): Promise<{ users: boolean; tables: Record<string, { read: number; assigned: number }> }> => {
    const users = await ctx.runMutation(internal.jobs.migrations.ensureOwner, {});
    const tables: Record<string, { read: number; assigned: number }> = {};
    for (const table of PER_USER_TABLES) {
      const sum = { read: 0, assigned: 0 };
      let cursor: string | null = null;
      for (;;) {
        const r: { read: number; assigned: number; cursor: string; isDone: boolean } = await ctx.runMutation(internal.jobs.migrations.assignOwnerPage, { table, cursor, ...(batch !== undefined ? { batch } : {}) });
        sum.read += r.read;
        sum.assigned += r.assigned;
        if (r.isDone) break;
        cursor = r.cursor;
      }
      tables[table] = sum;
    }
    return { users, tables };
  },
});

/** One page of one table for the report: how many rows, and how many have no `userId`. */
export const userIdReportPage = internalQuery({
  args: { table: tableName, cursor: v.optional(v.union(v.string(), v.null())), batch: v.optional(v.number()) },
  handler: async (ctx, { table, cursor, batch }): Promise<{ total: number; withoutUserId: number; cursor: string; isDone: boolean }> => {
    const page = await ctx.db.query(table).paginate({ cursor: cursor ?? null, numItems: Math.max(1, Math.floor(batch ?? PAGE_SIZE[table])) });
    return { total: page.page.length, withoutUserId: page.page.filter((r) => (r as { userId?: string }).userId === undefined).length, cursor: page.continueCursor, isDone: page.isDone };
  },
});

/**
 * ADR-039: per table, the number of rows and the number of rows with no `userId`, read page by page (a query alone could not read a big table).
 *   npx convex run jobs/migrations:userIdReport '{}'
 * Returns `{ ownerUser, tables: { <table>: { total, withoutUserId } }, withoutUserId }` where the last field is the sum. Deploy point 2 may only
 * be deployed when `withoutUserId` is 0 and `ownerUser` is true. Reads only; changes nothing.
 */
export const userIdReport = internalAction({
  args: { batch: v.optional(v.number()) },
  handler: async (ctx, { batch }): Promise<{ ownerUser: boolean; tables: Record<string, { total: number; withoutUserId: number }>; withoutUserId: number }> => {
    const tables: Record<string, { total: number; withoutUserId: number }> = {};
    let withoutUserId = 0;
    for (const table of PER_USER_TABLES) {
      const sum = { total: 0, withoutUserId: 0 };
      let cursor: string | null = null;
      for (;;) {
        const r: { total: number; withoutUserId: number; cursor: string; isDone: boolean } = await ctx.runQuery(internal.jobs.migrations.userIdReportPage, { table, cursor, ...(batch !== undefined ? { batch } : {}) });
        sum.total += r.total;
        sum.withoutUserId += r.withoutUserId;
        if (r.isDone) break;
        cursor = r.cursor;
      }
      tables[table] = sum;
      withoutUserId += sum.withoutUserId;
    }
    const ownerUser = await ctx.runQuery(internal.jobs.migrations.hasOwner, {});
    return { ownerUser, tables, withoutUserId };
  },
});

/** True when the `users` row of the owner exists (read by the report). */
export const hasOwner = internalQuery({
  args: {},
  handler: async (ctx): Promise<boolean> => (await ctx.db.query("users").withIndex("by_userId", (q) => q.eq("userId", OWNER_USER_ID)).unique()) !== null,
});
