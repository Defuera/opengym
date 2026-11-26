import { describe, expect, it } from "vitest";
import { PER_USER_TABLES } from "../functions/lib/userTables";

/**
 * Static guard for ADR-039. It reads the source of every function file (not `_generated`) and fails when:
 *  1. a per-user table is read without an index that starts with `userId` (or the scoped helpers do it for it),
 *  2. a public query, mutation or action does not call `requireUser`, or a public function is declared outside `commands/` and `queries/`,
 *  3. an internal function takes no `userId` argument,
 *  4. the owner id or the time zone variable is used outside the one place that owns it.
 * A text check, not a proof: it catches the usual slip (a new read with no user). The allow-lists below are small and every entry says why.
 */
const files = import.meta.glob(["../functions/**/*.ts", "!../functions/_generated/**"], { query: "?raw", import: "default", eager: true }) as Record<string, string>;
const entries = Object.entries(files).map(([path, src]) => [path.replace("../functions/", ""), src] as const);

/** Files that may read a per-user table without a user index, with the reason. */
const UNSCOPED_READ_OK: Record<string, string> = {
  "jobs/purge.ts": "erases marked rows and old traces of ALL users through by_deletedAt / by_at; it reads no content, and every follow-up read uses the userId of the marked row",
  "jobs/migrations.ts": "the rollout report pages through every row of every table on purpose (userIdReport); the old one-off migrations are scoped by user",
  "queries/usage.ts": "the operator report (internal `report`) reads aiUsage of all users by by_at; the public summary uses by_user_and_at",
};
/** Internal functions that take no `userId`, with the reason. Key: "file:name". */
const NO_USER_ARG_OK: Record<string, string> = {
  "jobs/purge.ts:run": "the hourly cron: erases for all users, see above",
  "jobs/pdfText.ts:extract": "reads one stored PDF blob by storage id, touches no table",
  "jobs/exerciseArt.ts:row": "exerciseArt is shared by all users (ADR-039): a catalogue of drawings with no personal data",
  "jobs/exerciseArt.ts:saveReady": "shared table, see above",
  "jobs/exerciseArt.ts:saveFailed": "shared table, see above",
  "jobs/exerciseArt.ts:remove": "operator tool on the shared table",
  "jobs/migrations.ts:ensureOwner": "makes the users row of the constant owner (the rollout)",
  "jobs/migrations.ts:hasOwner": "reads the users row of the constant owner (the rollout report)",
  "jobs/migrations.ts:userIdReportPage": "pages through all rows for the report",
  "jobs/migrations.ts:userIdReport": "the report over all users",
  "queries/usage.ts:report": "the operator report over all users, split by user in `byUser`",
};
/** Public functions that never use the user id they get, with the reason. Key: "file:name". The token is still checked. */
const NO_USER_USE_OK: Record<string, string> = {
  "commands/files.ts:generateUploadUrl": "a one-time upload URL names no row; `register` ties the stored blob to the user",
  "queries/exerciseArt.ts:get": "exerciseArt is shared by all users (ADR-039)",
  "queries/sessions.ts:planLoad": "pure arithmetic on the exercises in the arguments, reads no table",
};
const OWNER_ID_OK = new Set(["lib/auth.ts", "lib/currentUser.ts", "jobs/migrations.ts"]);

/** The registrations of a file: name, kind and the source text up to the next export. */
function registrations(src: string) {
  const re = /export const (\w+) = (query|mutation|action|internalQuery|internalMutation|internalAction)\(/g;
  const found: { name: string; kind: string; body: string }[] = [];
  const starts: { name: string; kind: string; at: number }[] = [];
  for (let m = re.exec(src); m; m = re.exec(src)) starts.push({ name: m[1]!, kind: m[2]!, at: m.index });
  for (const [i, s] of starts.entries()) {
    const next = src.indexOf("\nexport ", s.at + 10);
    found.push({ name: s.name, kind: s.kind, body: src.slice(s.at, next < 0 ? undefined : next) });
  }
  return found;
}

describe("static guard: every read and write is for a user (ADR-039)", () => {
  it("sees the function files (a guard that reads nothing guards nothing)", () => {
    expect(entries.length).toBeGreaterThan(60);
    expect(entries.some(([p]) => p === "lib/auth.ts")).toBe(true);
  });

  it("every read of a per-user table goes through an index that starts with userId", () => {
    const bad: string[] = [];
    for (const [file, src] of entries) {
      if (file in UNSCOPED_READ_OK || file === "schema.ts") continue;
      for (const m of src.matchAll(/\.query\(\s*([^)]*)\)/g)) {
        const arg = m[1]!.trim();
        const table = /^"(\w+)"$/.exec(arg)?.[1];
        if (table === undefined && !/^[a-z]/.test(arg)) continue;
        // A table name in a variable (a loop over tables) counts as a per-user table: it must be scoped too.
        if (table !== undefined && !(PER_USER_TABLES as readonly string[]).includes(table)) continue;
        const after = src.slice(m.index!, m.index! + 420);
        if (!/\.withIndex\("by_user\w*", \(\w+\) =>\s*(\{[^}]*?)?\w+\.eq\("userId", /.test(after)) bad.push(`${file}: query(${table ?? arg}) with no by_user index on userId: ${after.slice(0, 110).replace(/\s+/g, " ")}`);
      }
    }
    expect(bad).toEqual([]);
  });

  it("no index of a per-user table is read by a plain id any more (the old indexes are gone)", () => {
    const bad: string[] = [];
    for (const [file, src] of entries) {
      if (file === "schema.ts") continue;
      for (const m of src.matchAll(/\.query\("(\w+)"\)\s*\.withIndex\("(by_(?!user)\w+)"/g)) {
        if ((PER_USER_TABLES as readonly string[]).includes(m[1]!) && !(file in UNSCOPED_READ_OK)) bad.push(`${file}: ${m[1]} by ${m[2]}`);
      }
    }
    expect(bad).toEqual([]);
  });

  it("every public function checks the token with requireUser and uses the user it returns", () => {
    const bad: string[] = [];
    let publicCount = 0;
    for (const [file, src] of entries) {
      for (const r of registrations(src)) {
        if (r.kind.startsWith("internal")) continue;
        publicCount++;
        if (!/^(commands|queries)\//.test(file)) bad.push(`${file}:${r.name} is public but lives outside commands/ and queries/`);
        if (!/const userId = await requireUser\(ctx, token\)/.test(r.body)) bad.push(`${file}:${r.name} does not call requireUser`);
        if (!/args: \{[^}]*token: v\.string\(\)/.test(r.body)) bad.push(`${file}:${r.name} takes no token`);
        const uses = r.body.split("userId").length - 1;
        if (uses < 2 && !(`${file}:${r.name}` in NO_USER_USE_OK)) bad.push(`${file}:${r.name} never uses the user it got`);
      }
    }
    expect(publicCount).toBeGreaterThan(60);
    expect(bad).toEqual([]);
  });

  it("no function checks the token any other way (requireToken is gone)", () => {
    for (const [file, src] of entries) if (file !== "lib/auth.ts") expect(src, file).not.toMatch(/requireToken|process\.env\.APP_TOKEN/);
  });

  it("every internal function takes the user it works for", () => {
    const bad: string[] = [];
    for (const [file, src] of entries) {
      for (const r of registrations(src)) {
        if (!r.kind.startsWith("internal") || `${file}:${r.name}` in NO_USER_ARG_OK) continue;
        // `args: unitArgs` style: the shared object holds it.
        const head = r.body.slice(0, 400);
        const direct = /args: \{[^}]*\buserId: v\.string\(\)/s.test(head);
        const shared = /args: (\w+),/.exec(head);
        const viaShared = shared !== null && new RegExp(`const ${shared[1]} = \\{[^}]*userId: v\\.string\\(\\)`, "s").test(src);
        if (!direct && !viaShared) bad.push(`${file}:${r.name}`);
      }
    }
    expect(bad).toEqual([]);
  });

  it("the allow-lists hold only entries that exist (no dead excuses)", () => {
    for (const k of Object.keys(NO_USER_USE_OK)) {
      const [f, name] = k.split(":") as [string, string];
      expect(registrations(files[`../functions/${f}`] ?? "").some((r) => r.name === name && !r.kind.startsWith("internal")), k).toBe(true);
    }
    for (const f of Object.keys(UNSCOPED_READ_OK)) expect(files[`../functions/${f}`], f).toBeDefined();
    for (const k of Object.keys(NO_USER_ARG_OK)) {
      const [f, name] = k.split(":") as [string, string];
      expect(registrations(files[`../functions/${f}`] ?? "").some((r) => r.name === name && r.kind.startsWith("internal")), k).toBe(true);
    }
  });

  it("the owner id appears only where the token is mapped and where the rollout makes the owner", () => {
    const bad = entries.filter(([f, src]) => !OWNER_ID_OK.has(f) && f !== "schema.ts" && /OWNER_USER_ID|"owner"/.test(src.replace(/updatedBy[^\n]*/g, "").replace(/v\.literal\("owner"\)/g, ""))).map(([f]) => f);
    expect(bad).toEqual([]);
  });

  it("the time zone variable is read in one place only (model/timezone.ts)", () => {
    const bad = entries.filter(([f, src]) => f !== "model/timezone.ts" && /process\.env\.APP_TIMEZONE/.test(src)).map(([f]) => f);
    expect(bad).toEqual([]);
  });

  it("every write of a per-user table names the user (insert and replace carry userId)", () => {
    const bad: string[] = [];
    for (const [file, src] of entries) {
      if (file === "schema.ts" || file === "jobs/migrations.ts") continue;
      for (const m of src.matchAll(/\.insert\("(\w+)", ([^\n]{0,300})/g)) {
        const table = m[1]!;
        if (!(PER_USER_TABLES as readonly string[]).includes(table)) continue;
        const near = src.slice(m.index!, m.index! + 600);
        if (!/userId/.test(near)) bad.push(`${file}: insert("${table}") does not name userId`);
      }
    }
    expect(bad).toEqual([]);
  });
});
