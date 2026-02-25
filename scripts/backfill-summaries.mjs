/**
 * Backfill AI session summaries for the last N weeks.
 * Usage: node scripts/backfill-summaries.mjs [weeksBack=3]
 *
 * Requires env vars:
 *   CONVEX_DEPLOYMENT_URL  — e.g. https://wary-mockingbird-65.eu-west-1.convex.cloud
 *   CONVEX_DEPLOY_KEY      — admin deploy key (can call internal functions)
 */

import { readFileSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";

// Load .env.local if present
const __dir = dirname(fileURLToPath(import.meta.url));
const envPath = resolve(__dir, "../.env.local");
try {
  const envContent = readFileSync(envPath, "utf8");
  for (const line of envContent.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eqIdx = trimmed.indexOf("=");
    if (eqIdx < 0) continue;
    const key = trimmed.slice(0, eqIdx).trim();
    const val = trimmed.slice(eqIdx + 1).trim();
    if (!process.env[key]) process.env[key] = val;
  }
} catch {
  // no .env.local, rely on actual env vars
}

const CONVEX_URL = process.env.CONVEX_DEPLOYMENT_URL;
const DEPLOY_KEY = process.env.CONVEX_DEPLOY_KEY;

if (!CONVEX_URL || !DEPLOY_KEY) {
  console.error("Missing CONVEX_DEPLOYMENT_URL or CONVEX_DEPLOY_KEY");
  process.exit(1);
}

const weeksBack = parseInt(process.argv[2] ?? "3", 10);
const cutoff = Date.now() - weeksBack * 7 * 24 * 60 * 60 * 1000;

const headers = {
  "Content-Type": "application/json",
  Authorization: `Convex ${DEPLOY_KEY}`,
};

async function convexQuery(path, args = {}) {
  const res = await fetch(`${CONVEX_URL}/api/query`, {
    method: "POST",
    headers,
    body: JSON.stringify({ path, args }),
  });
  const json = await res.json();
  if (json.status === "error") throw new Error(`Query ${path} failed: ${json.errorMessage}`);
  return json.value;
}

async function convexAction(path, args = {}) {
  const res = await fetch(`${CONVEX_URL}/api/action`, {
    method: "POST",
    headers,
    body: JSON.stringify({ path, args }),
  });
  const json = await res.json();
  if (json.status === "error") throw new Error(`Action ${path} failed: ${json.errorMessage}`);
  return json.value;
}

// ── 1. Get user ──────────────────────────────────────────────────────────────
console.log("Looking up default user...");
const user = await convexQuery("users:getDefaultUser", {});
if (!user) {
  console.error("No default user found in database.");
  process.exit(1);
}
console.log(`User: ${user.name} (${user._id})`);

// ── 2. Get completed sessions from last N weeks ───────────────────────────────
console.log(`Fetching completed sessions from last ${weeksBack} weeks...`);

const allSessions = await convexQuery("sessions:listRecentCompleted", {
  userId: user._id,
  limit: 100,
});
const recentCompleted = allSessions.filter((s) => s.date >= cutoff);

console.log(`Found ${recentCompleted.length} completed sessions in range`);

if (recentCompleted.length === 0) {
  console.log("Nothing to backfill.");
  process.exit(0);
}

// ── 3. Get existing summaries ────────────────────────────────────────────────
const weeklySummaries = await convexQuery("sessions:getWeeklySessionsWithSummaries", {
  userId: user._id,
  weeksBack: weeksBack + 1,
});

// Collect session IDs that already have summaries
const hasSummary = new Set();
for (const week of weeklySummaries) {
  for (const s of week.sessions ?? []) {
    if (s.summary) hasSummary.add(s.sessionId);
  }
}
console.log(`${hasSummary.size} sessions already have summaries`);

// ── 4. Generate missing summaries ────────────────────────────────────────────
let generated = 0;
let skipped = 0;
let errors = 0;

for (const session of recentCompleted) {
  const sessionDate = new Date(session.date).toISOString().slice(0, 10);
  process.stdout.write(`  Session ${session._id} (${sessionDate}) ... `);

  if (hasSummary.has(session._id)) {
    console.log("✓ already has summary, skipping");
    skipped++;
    continue;
  }

  // Generate summary
  try {
    await convexAction("aiSessionSummary:generateSessionSummary", {
      sessionId: session._id,
    });
    console.log("✅ generated");
    generated++;
    // Small delay to avoid hammering OpenAI
    await new Promise((r) => setTimeout(r, 1500));
  } catch (err) {
    console.log(`❌ error: ${err.message}`);
    errors++;
  }
}

console.log(`\nDone. Generated: ${generated}, Skipped: ${skipped}, Errors: ${errors}`);
