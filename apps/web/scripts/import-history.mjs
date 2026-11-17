// Import historical workout data from CSV
import { readFileSync } from "fs";

const CONVEX_URL = "https://wary-mockingbird-65.eu-west-1.convex.cloud";

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

// Simple CSV parser that handles quoted fields with commas
function parseCSV(content) {
  const lines = content.split("\n").filter(l => l.trim());
  const headers = parseCSVLine(lines[0]);
  return lines.slice(1).map(line => {
    const values = parseCSVLine(line);
    const obj = {};
    headers.forEach((h, i) => obj[h.trim()] = (values[i] || "").trim());
    return obj;
  }).filter(r => r.date);
}

function parseCSVLine(line) {
  const result = [];
  let current = "";
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') {
      inQuotes = !inQuotes;
    } else if (ch === "," && !inQuotes) {
      result.push(current);
      current = "";
    } else {
      current += ch;
    }
  }
  result.push(current);
  return result;
}

// Muscle group inference
function inferMuscleGroup(exerciseName) {
  const name = exerciseName.toLowerCase();
  if (/squat|leg press|lunge|leg curl|calf|adduct|abduct|glute|hip|quad|hamstring|prone leg/.test(name)) return "Legs";
  if (/bench|chest|pec|fly|push.up|incline.*press|dip|pullover/.test(name)) return "Chest";
  if (/pull.up|pulldown|row|lat|pullover|deadlift|back|iso.lat|hammer strength/.test(name)) return "Back";
  if (/shoulder|overhead press|lateral raise|reverse fly|face pull|upright/.test(name)) return "Shoulders";
  if (/bicep|curl|preacher/.test(name)) return "Arms";
  if (/tricep|pushdown|skull|extension/.test(name)) return "Arms";
  if (/plank|ab|core|crunch|sit.up|l.sit|gymnast/.test(name)) return "Core";
  if (/run|bike|cardio|swim/.test(name)) return "Cardio";
  return "Other";
}

// Parse sets from the varied format
function parseSets(setsStr) {
  if (!setsStr) return [];
  const s = setsStr.trim();

  // Skip non-weight entries
  if (/^done$/i.test(s)) return [];
  if (/min hold/i.test(s)) return [];
  if (/session/i.test(s)) return [];
  if (/^[0-9]+:[0-9]+ \/ [0-9.]+ km/.test(s)) return []; // running time
  if (/arms/i.test(s)) return [];
  if (/gymnast|mobility|prehab/i.test(s)) return [];
  if (/^[0-9]+ min/.test(s)) return [];

  const result = [];

  // Normalize: split on →
  const parts = s.split(/\s*→\s*/);

  for (const part of parts) {
    const trimmed = part.trim();
    if (!trimmed) continue;

    // "8×empty" or "5×empty" — bodyweight warmup, skip weight
    if (/^\d+(\.\d+)?×empty$/i.test(trimmed)) {
      const reps = Math.round(parseFloat(trimmed));
      result.push({ reps, weight: 0 });
      continue;
    }

    // "3×8×60" or "2×10×25" — sets×reps×weight
    const tripleMatch = trimmed.match(/^(\d+(?:\.\d+)?)×(\d+(?:\.\d+)?)×(\d+(?:\.\d+)?)$/);
    if (tripleMatch) {
      const sets = Math.round(parseFloat(tripleMatch[1]));
      const reps = Math.round(parseFloat(tripleMatch[2]));
      const weight = parseFloat(tripleMatch[3]);
      for (let i = 0; i < sets; i++) result.push({ reps, weight });
      continue;
    }

    // "6×40" — reps×weight
    const pairMatch = trimmed.match(/^(\d+(?:\.\d+)?)×(\d+(?:\.\d+)?)$/);
    if (pairMatch) {
      const reps = Math.round(parseFloat(pairMatch[1]));
      const weight = parseFloat(pairMatch[2]);
      result.push({ reps, weight });
      continue;
    }

    // "10×20/arm" — per-arm weight, treat as total (×2)
    const perArmMatch = trimmed.match(/^(\d+(?:\.\d+)?)×(\d+(?:\.\d+)?)\/arm$/i);
    if (perArmMatch) {
      const reps = Math.round(parseFloat(perArmMatch[1]));
      const weight = parseFloat(perArmMatch[2]) * 2;
      result.push({ reps, weight });
      continue;
    }

    // "4 rounds: (8,7,7) (9,7,6)" — pull-up rounds, extract first numbers per group
    const roundsMatch = trimmed.match(/(\d+) rounds?:\s*([\s\S]+)/i);
    if (roundsMatch) {
      const groups = roundsMatch[2].match(/\(([^)]+)\)/g) || [];
      for (const g of groups) {
        const nums = g.replace(/[()]/g, "").split(",").map(n => parseInt(n.trim())).filter(Boolean);
        for (const reps of nums) result.push({ reps, weight: 0 });
      }
      continue;
    }

    // "9, 7, 5" or "12, 7, 6" — just reps (pull-ups, bodyweight)
    const commaRepsMatch = trimmed.match(/^[\d,\s]+$/);
    if (commaRepsMatch) {
      const nums = trimmed.split(",").map(n => parseInt(n.trim())).filter(n => !isNaN(n));
      for (const reps of nums) result.push({ reps, weight: 0 });
      continue;
    }

    // "9 reps" — single set bodyweight
    const singleRepsMatch = trimmed.match(/^(\d+)\s+reps?$/i);
    if (singleRepsMatch) {
      result.push({ reps: parseInt(singleRepsMatch[1]), weight: 0 });
      continue;
    }

    // "12×20 → 8×20" (already handled above via parts split)
    // "5×10-15 (25-50 kg)" — range, take midpoint
    const rangeMatch = trimmed.match(/^(\d+)×[\d-]+\s*\((\d+)-(\d+)\s*kg\)/i);
    if (rangeMatch) {
      const sets = parseInt(rangeMatch[1]);
      const weight = (parseInt(rangeMatch[2]) + parseInt(rangeMatch[3])) / 2;
      for (let i = 0; i < sets; i++) result.push({ reps: 12, weight });
      continue;
    }
  }

  return result.filter(s => !isNaN(s.reps) && !isNaN(s.weight) && s.reps > 0);
}

async function main() {
  // Read CSV
  const csvPath = process.argv[2];
  if (!csvPath) {
    console.error("Usage: node import-history.mjs <path-to-csv>");
    process.exit(1);
  }

  const content = readFileSync(csvPath, "utf8");
  const rows = parseCSV(content);

  // Get user
  const userId = await callMutation("users:getOrCreateDefaultUser", {});
  console.log("User:", userId);

  // Group by date
  const byDate = new Map();
  for (const row of rows) {
    if (!byDate.has(row.date)) byDate.set(row.date, []);
    byDate.get(row.date).push(row);
  }

  let sessionCount = 0;
  let skippedExercises = 0;

  for (const [dateStr, exercises] of [...byDate.entries()].sort()) {
    const date = new Date(dateStr + "T12:00:00Z").getTime();
    const focus = exercises[0]?.focus || "General";

    const exerciseList = [];
    let order = 0;

    for (const row of exercises) {
      const sets = parseSets(row.sets);
      if (sets.length === 0) {
        skippedExercises++;
        continue; // skip non-weight exercises
      }

      exerciseList.push({
        name: row.exercise,
        muscleGroup: inferMuscleGroup(row.exercise),
        order: order++,
        sets: sets.map((s, i) => ({ ...s, order: i })),
      });
    }

    if (exerciseList.length === 0) {
      console.log(`  Skipping ${dateStr} (${focus}) — no quantifiable exercises`);
      continue;
    }

    const sessionId = await callMutation("sessions:create", {
      userId,
      date,
      status: "completed",
      exercises: exerciseList,
    });

    sessionCount++;
    console.log(`✓ ${dateStr} — ${focus} — ${exerciseList.length} exercises → ${sessionId}`);
  }

  console.log(`\nDone! Imported ${sessionCount} sessions, skipped ${skippedExercises} non-weight exercises.`);
}

main().catch(console.error);
