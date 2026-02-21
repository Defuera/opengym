// Delete all test/UI-testing sessions from this week, keeping only the real imported ones
const CONVEX_URL = "https://wary-mockingbird-65.eu-west-1.convex.cloud";
const USER_ID = "jh728j0gfntw77v5en073z035s81bksc";

// These are the real imported sessions — keep them
const KEEP_IDS = new Set([
  "j9700xsfqd31an9c4nrwwthcqd81jet8", // Feb 17 — Upper Body (from CSV)
  "j97fcta7fbgy99v18nv1m1vnc981kt98", // Feb 19 — Lower Body (manual import)
  "j97fdzxg07kcaky97qeqvfxw5181kv4k", // Feb 20 — Upper Body (manual import)
]);

async function call(path, args) {
  const res = await fetch(`${CONVEX_URL}/api/${path.includes(":") ? "mutation" : "query"}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ path, args }),
  });
  const data = await res.json();
  if (data.status !== "success") throw new Error(`${path}: ${JSON.stringify(data)}`);
  return data.value;
}

async function callMutation(name, args) {
  const res = await fetch(`${CONVEX_URL}/api/mutation`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ path: name, args }),
  });
  const data = await res.json();
  if (data.status !== "success") throw new Error(`${name}: ${JSON.stringify(data)}`);
  return data.value;
}

async function callQuery(name, args) {
  const res = await fetch(`${CONVEX_URL}/api/query`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ path: name, args }),
  });
  const data = await res.json();
  if (data.status !== "success") throw new Error(`${name}: ${JSON.stringify(data)}`);
  return data.value;
}

async function main() {
  // Get all sessions (high limit to catch everything)
  const sessions = await callQuery("sessions:listWithDetails", { userId: USER_ID, limit: 200 });

  // Feb 16, 2026 00:00 UTC — start of this week
  const startOfThisWeek = Date.UTC(2026, 1, 16);

  const thisWeek = sessions.filter(s => s.date >= startOfThisWeek);
  console.log(`Found ${thisWeek.length} sessions this week`);

  const toDelete = thisWeek.filter(s => !KEEP_IDS.has(s._id));
  const toKeep = thisWeek.filter(s => KEEP_IDS.has(s._id));

  console.log(`Keeping ${toKeep.length} real sessions:`);
  toKeep.forEach(s => console.log(` ✓ ${new Date(s.date).toISOString().slice(0,10)} ${s._id}`));

  console.log(`Deleting ${toDelete.length} test sessions...`);
  let deleted = 0;
  for (const s of toDelete) {
    await callMutation("sessions:deleteSession", { id: s._id });
    console.log(` ✗ ${new Date(s.date).toISOString().slice(0,10)} ${s._id} (${s.status})`);
    deleted++;
  }

  console.log(`\nDone: ${deleted} test sessions deleted.`);
}

main().catch(console.error);
